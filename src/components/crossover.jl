
#######
### Crossover operator
#######
function crossover!(population::DataFrame, orig_entity::DataFrameRow, feature_groups::Vector{FeatureGroup}, feasible_space)

    gb = groupby( population[population.outc .== true,:], :mod )

    num_groups = size(keys(gb),1)

    for group1 in 1:num_groups
        parent1 = gb[group1][1,:]

        push!(population,parent1)
        population[end,:estcf] = false
        added_offspring = size(population,1)

        for (index, group) in enumerate(feature_groups)
            df = feasible_space[index]

            # check whether we can change the feature value to something else
            (isempty(df) || group.allCategorical || !any(parent1.mod[group.indexes])) && continue

            space = df[df.distance .< distanceFeatureGroup(parent1, orig_entity,group), :]
            isempty(space) && continue

            sampled_row = StatsBase.sample(1:nrow(space), StatsBase.FrequencyWeights(space.count), 1)

            push!(population,parent1)                                                  ## TODO: Do we want to do sample more cases here??
            population[end,group.names] = space[sampled_row, group.names]
            population[end,:estcf] = false

            sampled_row = StatsBase.sample(1:nrow(space), StatsBase.FrequencyWeights(space.count), 1)

            population[added_offspring,group.names] = space[sampled_row, group.names]  ## This might create duplicates!!
        end

        for group2 in group1+1:num_groups

            parent2 = gb[group2][1,:]

            modified_features::BitVector = parent1.mod .| parent2.mod

            # c = deepcopy(parent1)
            push!(population, parent1)
            c = population[end, :]
            c.estcf = false
            c.mod = parent1.mod .| parent2.mod

            for (index, group) in enumerate(feature_groups)
                df = feasible_space[index]

                # check whether we can change the feature value to something else
                (isempty(df) || !any(modified_features[group.indexes])) && continue

                changed_p1 = any(parent1.mod[group.indexes])
                changed_p2 = any(parent2.mod[group.indexes])

                if changed_p1 && changed_p2
                    c[group.names] = (rand(Bool) ? parent1[group.names] : parent2[group.names])
                elseif changed_p1
                    c[group.names] = parent1[group.names]
                elseif changed_p2
                    c[group.names] = parent2[group.names]
                end
            end
            push!(population, c)
        end
    end
end


function crossover!(manager::DataManager, orig_entity::DataFrameRow, feature_groups::Vector{FeatureGroup}, feasible_space::Vector{DataFrame})

    mod_list = collect(keys(manager.dict))
    num_groups = length(mod_list)

    # print(num_groups, size(manager))
    c3=DataFrame(orig_entity)
    c3.score=0.0
    c3.outc=false
    c3.estcf=false

    for group1 in 1:num_groups

        mod_parent1 = mod_list[group1]

        population = manager.dict[mod_parent1]
        parent1 = population[1,:]
        cols_parent1 = names(parent1)[1:end-3]

        push!(population,parent1)
        population[end,:estcf] = false
        added_offspring = size(population,1)

        ## Selective Mutation:
        for (index, group) in enumerate(feature_groups)
            df = feasible_space[index]

            # check whether we can change the feature value to something else
            (isempty(df) || group.allCategorical || !any(mod_parent1[group.indexes])) && continue

            group_dist = distanceFeatureGroup(parent1,orig_entity,group)
            rows::BitVector = df.distance .< group_dist

            space = df[rows, :]::DataFrame

            isempty(space) && continue

            sampled_row = StatsBase.sample(1:nrow(space), StatsBase.FrequencyWeights(space.count))

            push!(population,parent1)                                                  ## TODO: Do we want to do sample more cases here??
            population[end,group.names] = space[sampled_row, group.names]
            population[end,:estcf] = false

            sampled_row = StatsBase.sample(1:nrow(space), StatsBase.FrequencyWeights(space.count))

            population[added_offspring,group.names] = space[sampled_row, group.names]  ## This may add a duplicate!
        end

        ## Crossover:
        for group2 in group1+1:num_groups

            # println(group1, " ", group2)

            mod_parent2 = mod_list[group2]
            parent2 = manager.dict[mod_parent2][1,:]
            cols_parent2 = names(parent2)[1:end-3]

            modified_features::BitVector = mod_parent1 .| mod_parent2

            ## TODO: Can we improve this bit?

            #push!(manager, modified_features, (orig_entity[modified_features]..., score=0.0, outc=false, estcf=false))
            push!(manager, modified_features, c3[1,:])
            c = get_store(manager, modified_features)[end, :]

            # c1 = parent1
            # c2 = parent2
            # println(c)
            # println(manager.dict[modified_features])

            for (index, group) in enumerate(feature_groups)
                df = feasible_space[index]

                # check whether we can change the feature value to something else
                (isempty(df) || !any(modified_features[group.indexes])) && continue

                # println(mod_parent1[group.indexes]," -- ", mod_parent2[group.indexes], sum(mod_parent1[group.indexes]), " -- ", sum(mod_parent2[group.indexes]))
                p1_changed = any(mod_parent1[group.indexes])
                p2_changed = any(mod_parent2[group.indexes])

                if p1_changed && p2_changed
                    # TODO: We could have a case here where the other parent changed additional features, but we wouldn't change it?
                    if rand(Bool)
                        cols = [n for n in group.names if n in cols_parent1]
                        c[cols] = parent1[cols]
                    else
                        cols = [n for n in group.names if n in cols_parent2]
                        c[cols] = parent2[cols]
                    end
                elseif p1_changed
                    cols = [n for n in group.names if n in cols_parent1]
                    c[cols] = parent1[cols]
                elseif p2_changed
                    cols = [n for n in group.names if n in cols_parent2]
                    c[cols] = parent2[cols]
                end
            end
        end
    end
end
