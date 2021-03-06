"""
   ADDataset

A structure representing an anomaly detection dataset with one normal class and
multiple anomaly classes split according to their difficulty. 
"""
struct ADDataset
    normal::Array{Float, 2}
    easy::Array{Float, 2}
    medium::Array{Float, 2}
    hard::Array{Float, 2}
    very_hard::Array{Float, 2}
end

"""
   txt2array(file)

If the file does not exist, returns an empty 2D array. 
"""
txt2array(file::String) = isfile(file) ? readdlm(file) : Array{Float32,2}(undef,0,0)

""" 
    ADDataset(path)

Constructor for the Basicset struct using a folder in the Loda database.
Transposes the arrays so that instances are columns. If a file (anomaly class)
is missing, an empty array is in its place in the resulting structure.
"""
ADDataset(path::String) = (isdir(path)) ? ADDataset(
    txt2array(joinpath(path, "normal.txt"))',
    txt2array(joinpath(path, "easy.txt"))',
    txt2array(joinpath(path, "medium.txt"))',
    txt2array(joinpath(path, "hard.txt"))',
    txt2array(joinpath(path, "very_hard.txt"))',
    ) : error("$path - no such path exists.")

"""
    normalize(Y)

Scales down a 2 dimensional array so it has approx. standard normal distribution. 
Instance = column. 
"""
function normalize(Y::Array{T,2} where T<:Real)
    M, N = size(Y)
    mu = Statistics.mean(Y,dims=2);
    sigma = Statistics.var(Y,dims=2);

    # if there are NaN present, then sigma is zero for a given column -> 
    # the scaled down column is also zero
    # but we treat this more economically by setting the denominator for a given column to one
    # also, we deal with numerical zeroes
    den = sigma
    den[abs.(den) .<= 1e-15] .= 1.0
    den[den .== 0.0] .= 1.0
    den = repeat(sqrt.(den), 1, N)
    nom = Y - repeat(mu, 1, N)
    nom[abs.(nom) .<= 1e-8] .= 0.0
    Y = nom./den
    return Y
end

"""
   normalize(x,y)

Concatenate x and y along the 2nd axis, normalize them and split them again. 
"""
function normalize(x,y)
    M,N = size(x)
    data = cat(x, y, dims = 2)
    data = normalize(data)
    return data[:, 1:N], data[:, N+1:end]
end

"""
    vec2int(x)

Convert Float labels read by readdlm to Ints for prettier dataset names.
"""
vec2int(x::Vector) = map(y-> (typeof(y)<:Real) ? Int(y) : y, x) 

"""
    load_class_labels(path)

Load class labels saved in path.    
"""
load_class_labels(path) = vec2int(vec(readdlm(joinpath(path,"normal_labels.txt")))), 
    vec2int(vec(readdlm(joinpath(path,"medium_labels.txt"))))

"""
    get_processed_datapath()

Get the absolute path of UMAP data.
"""
get_processed_datapath() = joinpath(dirname(dirname(@__FILE__)), "processed")

"""
    get_umap_datapath()

Get the absolute path of UMAP data.
"""
get_umap_datapath() = joinpath(dirname(dirname(@__FILE__)), "umap")

"""
    get_raw_datapath()

Get the absolute path the raw data.
"""
get_raw_datapath() = joinpath(dirname(dirname(@__FILE__)), "raw")

"""
    get_synthetic_datapath()

Get the absolute path of UMAP data.
"""
get_synthetic_datapath() = joinpath(dirname(dirname(@__FILE__)), "synthetic")

"""
    get_loda_datapath()

Get the absolute path of Loda data.
"""
get_loda_datapath() = joinpath(dirname(dirname(@__FILE__)), "loda")

"""
    data_info(datapath)

Returns a DataFrame
"""
function data_info(datapath)
    datasets = readdir(datapath)
    df = DataFrame(
        :dataset=>String[],
        :dim=>Int[],
        :normal=>Int[],
        :easy=>Int[],
        :medium=>Int[],
        :hard=>Int[],
        :very_hard=>Int[]
        )
    for dataset in datasets
        GC.gc()
        data, _, _ = UCI.get_data(dataset, path = datapath)       
        push!(df, [dataset, size(data.normal,1), size(data.normal,2), size(data.easy,2), 
            size(data.medium,2), size(data.hard,2), size(data.very_hard,2)])
    end
    return df
end

# get just those dirs that match the dataset pattern
_match_pattern(dataset, path) =
     filter(x->x[1:length(dataset)]==dataset,
                filter(x->length(x)>=length(dataset), 
                readdir(path)))

"""
    get_data(dataset_name; path)

For a given dataset name, loads the data from given directory.  Returns a structure of
type ADDataset, normal and anomalous data class labels. If dataset is not a multiclass
problem, then the labels equal to nothing.
"""
function get_data(dataset::String; path::String = "")
    path = (path=="" ? get_processed_datapath() : path)
    dataset_dirs = _match_pattern(dataset, path)
    # non multiclass datasets are in the loda dir, so try again
    if length(dataset_dirs) == 0
        path = get_loda_datapath() 
        dataset_dirs = _match_pattern(dataset, path)
    end
    # if still nothing was found, throw an error
    (length(dataset_dirs)==0) ? error("specified dataset not found!") : nothing

    # for multiclass problems, extract just data from the master directory
    dir_name_lengths = length.(split.(dataset_dirs, "-"))
    dataset_dir = joinpath(path, dataset_dirs[dir_name_lengths.==minimum(dir_name_lengths)][1])

    # load data and class labels if available
    data = ADDataset(dataset_dir)
    if isfile(joinpath(dataset_dir, "normal_labels.txt"))
        normal_class_labels, anomaly_class_labels = load_class_labels(dataset_dir)
        normal_class_labels = string.(normal_class_labels)
        anomaly_class_labels = string.(anomaly_class_labels)
    else
        normal_class_labels, anomaly_class_labels = nothing, nothing
    end

    return data, normal_class_labels, anomaly_class_labels
end

"""
    get_data(dataset_name, subclass; path)

For a given dataset name, loads the subclass given by an index or subclass name.
"""
function get_data(dataset::String, subclass::Union{Int, String}; path::String = "")
    data, normal_class_labels, anomaly_class_labels = get_data(dataset; path=path)
    subsets = create_multiclass(data, normal_class_labels, anomaly_class_labels)
    Ns = length(subsets)
    if Ns == 1
        return data, normal_class_labels, anomaly_class_labels
    end
    if typeof(subclass) == Int
        subclass = min(Ns,subclass)
        nlabel = normal_class_labels[1]
        alabel = split(subsets[subclass][2], nlabel)[2][2:end]
        return subsets[subclass][1], normal_class_labels, fill(alabel, sum(anomaly_class_labels.==alabel))
    elseif typeof(subclass) == String
        inds = occursin.(subclass, [x[2] for x in subsets])
        if sum(inds)==0 error("no subclass $subclass in dataset $dataset") end
        return subsets[inds][1][1], normal_class_labels, fill(subclass,  sum(anomaly_class_labels.==subclass))
    end
end

"""
    get_umap_data(dataset_name; path)

For a given dataset name, loads the data from given directory.  Returns a structure of
type ADDataset, normal and anomalous data class labels. If dataset is not a multiclass
problem, then the labels equal to nothing.
"""
get_umap_data(dataset::String) = get_data(dataset, path=get_umap_datapath())

"""
    get_umap_data(dataset_name, subclass; path)

For a given dataset name, loads the data from given directory.  Returns a structure of
type ADDataset, normal and anomalous data class labels. If dataset is not a multiclass
problem, then the labels equal to nothing.
"""
get_umap_data(dataset::String, subclass::Union{Int, String}) =
    get_data(dataset, subclass; path=get_umap_datapath())
    
"""
    get_synthetic_data(dataset_name; path)

For a given synthetic dataset name, loads the data from given directory. Returns a structure of
type ADDataset.
"""
function get_synthetic_data(dataset::String; path::String = "")
    path = (path=="" ? get_synthetic_datapath() : path)
    dataset_dir = joinpath(path, dataset)
    return ADDataset(dataset_dir)
end

"""
    get_loda_data(dataset)

For a given dataset name, loads the Loda data. Returns a structure of
type ADDataset and two empty placeholder variables.
"""
function get_loda_data(dataset::String)
    loda_path = get_loda_datapath()
    get_data(dataset, path=loda_path)
end

"""
    get_processed_data(dataset::String)

Get the processed (multiclass) data.
"""
function get_processed_data(dataset::String)
    path = joinpath(get_processed_datapath(), dataset)
    path = isdir(joinpath(path, dataset)) ? path : get_loda_datapath() 
    get_data(dataset, path=path)
end

"""
    create_multiclass(data::ADDataset, normal_labels, anomaly_labels)

From given labels, return an iterable over all multiclass subproblems and the subproblem names. 
Works even if the problem is not multiclass.
"""
create_multiclass(data::ADDataset, normal_labels, anomaly_labels) = 
    (normal_labels==nothing) ? [(data, "")] : [(ADDataset(data.normal, 
                                                Array{Float32,2}(undef,0,0),
                                                data.medium[:,anomaly_labels.==class],
                                                Array{Float32,2}(undef,0,0),
                                                Array{Float32,2}(undef,0,0)), "$(normal_labels[1])-$(class)"
                                                ) for class in unique(anomaly_labels)]
                        
"""
    split_data(data::ADDataset, p::Real=0.8, contamination::Real=0.0; seed = nothing, difficulty = nothing,
        standardize=false)

Creates training and testing data from a given ADDataset struct. 
p is the ratio of training to testing dataset_name
contamination is the contamination of the training dataset
"""
function split_data(data::ADDataset, p::Real=0.8, contamination::Real=0.0; 
    test_contamination=nothing, seed = nothing, difficulty = nothing, 
    standardize=false)
    @assert 0 <= p <= 1
    normal = data.normal
    if difficulty == nothing # sample all anomaly classes into the test dataset
        anomalous = Array{Float,2}(undef,size(data.normal,1),0)
        for diff in filter(y-> y!= :normal, [a for a in fieldnames(typeof(data))])
            x = getfield(data,diff)
            if prod(size(x)) != 0
                anomalous = hcat(anomalous, x)
            end
        end
    elseif typeof(difficulty) == Array{Symbol,1}
        anomalous = Array{Float,2}(undef,size(data.normal,1),0)
        for diff in intersect(difficulty, fieldnames(typeof(data)))
            x = getfield(data,diff)
            if prod(size(x)) != 0
                anomalous = hcat(anomalous, x)
            end
        end
    else
        anomalous = getfield(data, difficulty)
        if prod(size(anomalous)) == 0
            error("no data of given difficulty level!")
        end
    end

    # shuffle the data
    (seed == nothing) ? nothing : Random.seed!(seed)
    N = size(normal,2)
    normal = normal[:,StatsBase.sample(1:N, N, replace = false)]
    Na = size(anomalous,2)
    anomalous = anomalous[:,StatsBase.sample(1:Na, Na, replace = false)]
    Random.seed!() # reset the seed

    # normalize the data if necessary (so that they have 0 mean and unit variance)
    if standardize
        normal, anomalous = normalize(normal, anomalous)
    end

    # split the data
    # TODO - maybe change this so the contamination is anomal/all and not anomal/normal?
    Ntr = Int(floor(p*N))
    Natr = min(Int(floor(Ntr*contamination)), Int(floor(Na/2)))
    if test_contamination == nothing
        Natst = Na - Natr
    else
        Natst = min(Int(floor(test_contamination*(N-Ntr))), Na - Natr)
    end
    return hcat(normal[:,1:Ntr], anomalous[:,1:Natr]), vcat(fill(0,Ntr), fill(1,Natr)), # training data and labels
        hcat(normal[:,Ntr+1:end], anomalous[:,Natr+1:Natr+Natst]), vcat(fill(0,N-Ntr), fill(1,Natst)) # testing data and labels
end

"""
    split_val_test(x,y)

Split data `x` and labels `y` to halves, preserving the ratios of positive and negative samples.
"""
function split_val_test(x,y)
    n1 = sum(y)
    n0 = length(y) - n1
    n1n = floor(Int, n1/2)
    n0n = floor(Int, n0/2)
    inds1 = y.== 1
    inds0 = y.== 0
    val_x = hcat(x[:,inds0][:,1:n0n], x[:,inds1][:,1:n1n])
    val_y = vcat(y[inds0][1:n0n], y[inds1][1:n1n])
    test_x = hcat(x[:,inds0][:,n0n+1:2*n0n], x[:,inds1][:,n1n+1:2*n1n])
    test_y = vcat(y[inds0][n0n+1:2*n0n], y[inds1][n1n+1:2*n1n])
    return val_x, val_y, test_x, test_y
end
