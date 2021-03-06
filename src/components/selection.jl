

## Selection operator which finds the top-k CF entities
function selection!(population::DataFrame, k::Int64, orig_entity::DataFrameRow, features::Dict{String,Feature}, classifier, desired_class;
    norm_ratio::Array{Float64,1}=default_norm_ratio,
    convergence_k::Int=10,
    distance_temp::Vector{Float64}=Vector{Float64}())

    preds = score(classifier, population, desired_class)
    # preds = score_full_entity(classifier, population, desired_class)

    if length(distance_temp) < size(population,1)*4
        @warn "We increase the size of distance_temp in selection operator"
        resize!(distance_temp, size(population,1)*4)
    end

    dist = distance(population, orig_entity, features, distance_temp; norm_ratio=norm_ratio)
    for i in 1:nrow(population)
        p = (preds[i] > 0.5)
        population[i, :score] = dist[i] + (!p ? 2.0 - preds[i] : 0.0)
        population[i, :outc] = p
    end

    sort!(population, [:score])     # TODO:  Can we optimize this?

    # We keep the top-k counterfactuals
    (size(population,1) > k) && delete!(population, (k+1:size(population,1)))

    # Check if the top-K are established CFs, if so we have converged
    converged = all(population.estcf[1:convergence_k])

    # println(converged, convergence_k, population.estcf)

    # Update the established CFs
    population.estcf .= true

    return converged
end

predict(classifier::PartialRandomForestEval,entities,mod) = RandomForestEvaluation.predict(classifier,entities,mod)
predict(classifier::PartialMLPEval,entities,mod) = MLPEvaluation.predict(classifier,entities[:,1:end-NUM_EXTRA_COL+1],mod) # plus one because `mod` field is not in the DataManager entities

function selection!(manager::DataManager, k::Int64, orig_entity::DataFrameRow, features::Dict{String,Feature}, classifier::Union{PartialRandomForestEval, PartialMLPEval}, desired_class;
    norm_ratio::Array{Float64,1}=default_norm_ratio,
    convergence_k::Int=10,
    distance_temp::Vector{Float64}=Vector{Float64}())

    scores = Vector{Tuple{Float64,Bool}}()

    max_num_entity = maximum(nrow(entities) for entities in values(manager.dict))
    # println(max_num_entity, size(distance_temp))
    if length(distance_temp) < size(max_num_entity,1)*4
        @warn "We increase the size of distance_temp in selection operator"
        resize!(distance_temp,  4 * size(manager,1))
    end

    # Used by the distance function

    for (mod, entities) in manager.dict
        pred::Vector{Float64} = vec(predict(classifier, entities, mod))

        dist = distance(entities, orig_entity, features, distance_temp)
        entities.outc = pred .> 0.5
        entities.score = dist + map(predp -> !predp[2] ? 2.0 - predp[1] : 0.0, zip(pred, entities.outc))

        # dist + !p ? 2.0 - pred : 0.0
        append!(scores, zip(entities.score, entities.estcf))
    end

    sort!(scores, by=first)

    ## TODO: Make sure the below actually works
    if length(scores) > k
        keyList = collect(keys(manager))

        # We keep the top-k counterfactuals
        for mod in keyList
            entities = manager.dict[mod]
            keeps = entities.score .<= scores[k][1]
            select!(manager, mod, keeps)

            if isempty(manager.dict[mod])
                delete!(manager, mod)
            else
                sort!(manager.dict[mod], :score)
                manager.dict[mod].estcf .= true
            end
            # manager.dict[mod] = sort!(entities[keeps, :], :score)
            # updateCount!(manager, -(count(.!keeps)))
            # isempty(manager.dict[mod]) && delete!(manager, mod)
        end
    else
        for (mod,pop) in manager.dict
            sort!(pop, :score)
            pop.estcf .= true                         ## TODO: Test this
        end
    end

    converged = all(last.(scores[1:convergence_k]))
    return converged
end

function selection!(manager::DataManager, k::Int64, orig_entity::DataFrameRow, features::Dict{String,Feature}, classifier::Union{MLJ.Machine, PyCall.PyObject}, desired_class;
    norm_ratio::Array{Float64,1}=default_norm_ratio,
    convergence_k::Int=10,
    distance_temp::Vector{Float64}=Vector{Float64}(undef,100))

    df = materialize(manager)

    res = selection!(df, k, orig_entity, features, classifier, desired_class;
        norm_ratio = norm_ratio, convergence_k = convergence_k, distance_temp = distance_temp)

    empty!(manager)
    for entities in groupby(df, :mod)
        append!(manager, entities[1,:mod], entities[:, Not(:mod)])
    end

    return res
end



