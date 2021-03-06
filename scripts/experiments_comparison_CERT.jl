
using Pkg; Pkg.activate(".")
using GeCo

include("naive_geco/NaiveGeco.jl")

using Printf
import Dates, JLD

function runExperiment(dataset::String, desired_class::Int64)

    include("$(dataset)/$(dataset)_setup_MACE.jl")
    
    features, groups = initializeFeatures(path*"/data_info.json", X)
    distance_temp = Array{Float64,1}(undef, 12)
    failInit = 0

    ## Use for the MACE comparison:
    predictions = ScikitLearn.predict_proba(classifier, MLJ.matrix(X))[:, desired_class+1]
    # predictions = broadcast(MLJ.pdf, MLJ.predict(classifier, X), desired_class)

    println("Total number of predictions: $(length(predictions))\n"*
        "Total number of positive predictions $(sum(predictions))\n"*
        "Total number of negative predictions $(length(predictions)-sum(predictions))")

    num_changed_gc = Array{Int64,1}()
    feat_changed_gc = Array{BitArray{1},1}()
    distances_gc = Array{Float64,1}()
    correct_outcome_gc = Array{Bool,1}()
    times_gc = Array{Float64,1}()
    num_explored_gc = Array{Int64,1}()
    num_generation_gc = Array{Int64,1}()
    avg_rep_size_gc= Array{Float64,1}()

    num_changed_naive = Array{Int64,1}()
    feat_changed_naive = Array{BitArray{1},1}()
    distances_naive = Array{Float64,1}()
    correct_outcome_naive = Array{Bool,1}()
    times_naive = Array{Float64,1}()
    num_explored_naive = Array{Int64,1}()
    num_generation_naive = Array{Int64,1}()
    avg_rep_size_naive= Array{Float64,1}()

    # Run explanation once for compilation
    explain(X[1, :], X, path, classifier; desired_class = desired_class)

    for ratio in ["l0l1", "l1"] # ["l0l1", "l1", "combined"]
        nratio =
            if ratio == "l1"
                [0.0, 1.0, 0.0, 0.0]
            elseif ratio == "l0l1"
                [0.5, 0.5, 0.0, 0.0]
            elseif ratio == "combined"
                [0.25, 0.25, 0.25, 0.25]
            end

        for gens in [100, 200, 300]

            num_explained = 0
            num_to_explain = 50000

            empty!(num_changed_gc)
            empty!(feat_changed_gc)
            empty!(distances_gc)
            empty!(correct_outcome_gc)
            empty!(times_gc)
            empty!(num_explored_gc)
            empty!(num_generation_gc)
            empty!(avg_rep_size_gc)

            empty!(num_changed_naive)
            empty!(feat_changed_naive)
            empty!(distances_naive)
            empty!(correct_outcome_naive)
            empty!(times_naive)
            empty!(num_explored_naive)
            empty!(num_generation_naive)
            empty!(avg_rep_size_naive)

            for i in 1:length(predictions)
                if (desired_class == 1 ? predictions[i]<0.5 : predictions[i]>0.5)
                    (i % 100 == 0) && println("$(@sprintf("%.2f", 100*num_explained/num_to_explain))% through .. ")

                    orig_entity = X[i, :]

                     # the naive
                     time = @elapsed explanation = explain_naive(orig_entity, X, path, classifier; desired_class=desired_class, verbose=false, norm_ratio=nratio, num_generations=gens)
                    if (explanation === nothing) 
                        print("fail to init naive")
                        failInit += 1
                        num_explained += 1
                        continue
                    end
                    dist =
		    	 if nrow(explanation) >= 3
			    distance(explanation[1:3, :], orig_entity, features, distance_temp; norm_ratio=[0, 1.0, 0, 0])
			 else 
			    distance(explanation, orig_entity, features, distance_temp; norm_ratio=[0, 1.0, 0, 0])
			 end
			 
                     # println("--", sum(explanation.mod[1]), explanation.mod[1:3], dist, argmin(dist))
 
                     changed_feats = falses(size(X,2))
                     for (fidx, feat) in enumerate(propertynames(X))
                         changed_feats[fidx] = (orig_entity[feat] != explanation[1,feat])
                     end
                     if (all(.!changed_feats))
                         return (explanation, orig_entity, i)
                     end
 
                     ## We only consider the top-explanation for this
                     push!(correct_outcome_naive, explanation[1,:outc]>0.5)
                     push!(feat_changed_naive, changed_feats)
                     push!(num_changed_naive, sum(changed_feats))
                     push!(distances_naive, dist[1])
                     push!(times_naive, time)

                    num_explained += 1
                    (num_explained >= num_to_explain) && break
                end
            end
            print(failInit)
                        
	    file_naive = "scripts/results/naive_exp/$(dataset)_naive_ga_experiment_ratio_$(ratio)_generations_$(gens).jld"
	    
            JLD.save(file_naive, "times", times_naive, "dist", distances_naive, "numfeat", num_changed_naive)

            println("
            Average number of features changed: $(mean(num_changed_naive))
            Average distances:                  $(mean(distances_naive)) (normalized: $((mean(distances_naive ./ size(X,2)))))
            Average times:                      $(mean(times_naive))
            Correct outcomes:                   $(mean(correct_outcome_naive))
            Saved to: $file_naive")
        end
    end
end

runExperiment("credit", 1)
runExperiment("adult", 1)

#runExperiment("compas", 1)
