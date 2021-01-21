using CSV, Statistics, DataFrames, MLJ, ScikitLearn

path = "data/allstate"
#data = CSV.File(path*"/train_set.csv"; limit=1000000) |> DataFrame
data = CSV.File(path*"/train_set.csv") |> DataFrame

data.NoClaim = [x == 0.0 ? 1 : 0 for x in data.Claim_Amount]

deletecols!(data, [:Row_ID, :Claim_Amount, :Blind_Submodel, :Household_ID, :NVCat, :OrdCat])

## UNDER SAMPLING TO CREATE A BALANCED DATASET
data = data[shuffle(1:size(data,1)), :]

data_groups = groupby(data, :NoClaim)
data_train = data_groups[1][1:size(data_groups[2],1), :]
append!(data_train, data_groups[2])
data_train = data_train[shuffle(1:nrow(data_train)),:]

# data_falses = data[(data.NoClaim .== false), :]
# data_truess = data[(data.NoClaim .== true), :]\
# X_trues = X[(y .== true), :]
# X_train = X_trues[1:size(X_false,1), :]
# append!(X_train, X_falses)
# X_train = X_train[shuffle(1:nrow(X_train)),:]

y, X = unpack(data_train, ==(:NoClaim), colname -> true);

X.Cat12[ismissing.(X.Cat12)] .= "?"
X.Cat12 = convert.(String,X.Cat12)

onehot_features = [:Cat1,:Cat2,:Cat3,:Cat4,:Cat5,:Cat6,:Cat7,:Cat8,:Cat9,:Cat10,:Cat11,:Cat12,:Blind_Make, :Blind_Model]

coerce!(X,
    :Cat1 => Multiclass,
    :Cat2 => Multiclass,
    :Cat3 => Multiclass,
    :Cat4 => Multiclass,
    :Cat5 => Multiclass,
    :Cat6 => Multiclass,
    :Cat7 => Multiclass,
    :Cat8 => Multiclass,
    :Cat9 => Multiclass,
    :Cat10 => Multiclass,
    :Cat11 => Multiclass,
    :Cat12 => Multiclass,
    :Blind_Make => Multiclass,
    :Blind_Model => Multiclass
    )

# change the target to the desired
y = categorical(y)

# split the dataset
train, test = partition(eachindex(y), 0.7, shuffle=true)

# one-hot encode EducationLevel
onehot_encoder = OneHotEncoder(; features=onehot_features, drop_last=false, ordered_factor=false)
onehot_machine = machine(onehot_encoder, X)
MLJ.fit!(onehot_machine)
X = MLJ.transform(onehot_machine, X)

# load the model
@sk_import neural_network: MLPClassifier
# it's not mlj tho
#mlj_classifier=MLPClassifier(hidden_layer_sizes=(200,100,100,))
mlj_classifier=MLPClassifier() ## hidden_layer_sizes=(10,10))

# Training
ScikitLearn.fit!(mlj_classifier,MLJ.matrix(X),vec(collect(Int, y)))

## Evaluation:
yhat_train = ScikitLearn.predict(mlj_classifier, MLJ.matrix(X[train,:]))
yhat_test = ScikitLearn.predict(mlj_classifier, MLJ.matrix(X[test,:]))

println("Accuracy train data: $(mean(yhat_train .== y[train]))")
println("Accuracy test data: $(mean(yhat_test .== y[test]))")

yhat = ScikitLearn.predict(mlj_classifier, MLJ.matrix(X))
first_neg = findfirst(yhat .!= 1)
println(first_neg)

orig_instance = X[first_neg,:]
classifier = initMLPEval(mlj_classifier,orig_instance)