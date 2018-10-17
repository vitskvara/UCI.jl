using Statistics, StatsBase, DelimitedFiles, TSne, PyPlot, CSV, DataFrames
import Base.cat

Float = Float32

"""
Structure representing the basic Loda anomaly dataset.
"""
struct Basicset
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
function txt2array(file::String)
    if isfile(file)
        x = readdlm(file)
    else
        x = Array{Float,2}(undef,0,0)
    end
    return x
end

""" 
    Basicset(path)

Outer constructor for the Basicset struct using a folder in the Loda database.
Transposes the arrays so that instances are columns.
"""
Basicset(path::String) = (isdir(path)) ? Basicset(
    transpose(txt2array(joinpath(path, "normal.txt"))),
    transpose(txt2array(joinpath(path, "easy.txt"))),
    transpose(txt2array(joinpath(path, "medium.txt"))),
    transpose(txt2array(joinpath(path, "hard.txt"))),
    transpose(txt2array(joinpath(path, "very_hard.txt"))),
    ) : error("No such path $path exists.")

"""
    cat(bs::Basicset)

Return an array consisting of all concatenated arrays in bs and 
indices identifying the original array boundaries.
"""
function cat(bs::Basicset)
    X = bs.normal
    inds = [size(X,2)]
    for field in filter(x -> x != :normal, [f for f in fieldnames(typeof(bs))])
        x = getfield(bs,field)
        m = size(x,2)
        if m!= 0
            X = Base.cat(X,x,dims=2)
        end
        push!(inds, m)
    end
    return X, inds
end

"""
    standardize(Y)

Scales down a 2 dimensional array so it has approx. standard normal distribution. 
Instance = column. 
"""
function standardize(Y::Array{T,2} where T<:Real)
    M, N = size(Y)
    mu = mean(Y,dims=2);
    sigma = var(Y,dims=2);

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
	save_format(path,cat_cols = nothing)

Call as save_format(dir, [1:3, 4:6]).
"""
function save_format(path,cat_cols = nothing)
	data = Basicset(path)
	M,N = size(data.normal)
	labels = fill(0,M)
	if cat_cols != nothing
		for (i,category) in enumerate(cat_cols)
			labels[category] .= i
		end
	end
	writedlm(joinpath(path,"data_types.txt"),labels)	    
end

"""
    uncat(X, inds)

Return a Basicset instance created from X with array boundaries indicated
in inds.
"""
function uncat(X, inds, trans = false)
    cinds = cumsum(inds)
    if trans
    	return Basicset(
            transpose(X[:,1:cinds[1]]), 
            transpose(X[:,cinds[1]+1:cinds[2]]),
            transpose(X[:,cinds[2]+1:cinds[3]]),
            transpose(X[:,cinds[3]+1:cinds[4]]),
            transpose(X[:,cinds[4]+1:cinds[5]])
            )
    else	
	    return Basicset(
	            X[:,1:cinds[1]], 
	            X[:,cinds[1]+1:cinds[2]],
	            X[:,cinds[2]+1:cinds[3]],
	            X[:,cinds[3]+1:cinds[4]],
	            X[:,cinds[4]+1:cinds[5]])
	end
end

"""
    nDpca(X, n)

Returns an n-dimensional representation of X using a PCA transform.
"""
nDpca(X, n) = transform(fit(PCA,X,maxoutdim=n),X)

"""
    nDtsne(X, n; [max_samples, args, kwargs])

Returns an n-dimensional representation of X using a TSne transform.
The arguments args and kwargs respond to the TSne.tsne function arguments.
The second return variable are the indices of sampled samples.
"""
function nDtsne(X, n, reduce_dims = 0, max_iter = 1000; perplexity = 15.0,
    max_samples = 1000, verbose = true, progress = true, kwargs...)
    M,N = size(X)
    uN = min(N,max_samples) # no. of used samples
    println("sampling $uN samples")
    sinds = sort(sample(1:N, uN, replace = false))
    Y = transpose(tsne(transpose(X[:,sinds]),n, reduce_dims, max_iter, perplexity;
                verbose = verbose, progress = progress, kwargs...))
    return Y, sinds
end

"""
    partition(xinds, sinds)

Compute number of samples in individual groups defined by original group indices
xinds and sample indices sinds.
"""
function partition(xinds, sinds)
    cxinds = [0; cumsum(xinds)]
    a = [length(sinds[cxinds[i] .< sinds .<= cxinds[i+1]]) for 
            i in 1:length(cxinds)-1]
    return a
end

"""
    savetxt(bs::Basicset, path)

Saves a Basicset to the folder "path" into individual .txt files.
"""
function savetxt(bs::Basicset, path, trans = true)
    mkpath(path)
    for field in fieldnames(typeof(bs))
        x = getfield(bs, field)
        if prod(size(x)) > 0
        	if trans
	            writedlm(string(joinpath(path, String(field)), ".txt"),transpose(x))
	        else
	        	writedlm(string(joinpath(path, String(field)), ".txt"),x)
	        end
        end
    end
end

"""
    dataset2D(bs::Basicset, variant = ["pca", "tsne"], normalize = true)

Transforms a Basicset into 2D representation using PCA or tSne. 
"""
function dataset2D(bs::Basicset, variant = "pca", normalize = true, max_samples = 2000,
	perplexity = 15.0)
    (variant in ["pca", "tsne"]) ? nothing : error("variant must be one of [pca, tsne]")
    X, inds = cat(bs)
    (normalize) ? X = standardize(X) : nothing
    if variant == "pca"
        return uncat(nDpca(X, 2), inds)
    else
        _X, sinds = nDtsne(X,2;max_samples=max_samples, perplexity=perplexity)
        _inds = partition(inds, sinds)
        return uncat(_X, _inds)
    end
end

"""
    dataset2D(inpath, outpath, variant = ["pca", "tsne"], normalize = true)

Transforms a dataset 
"""
function dataset2D(inpath, outpath, variant = "pca", normalize = true, max_samples = 2000,
	perplexity = 15.0)
    (variant in ["pca", "tsne"]) ? nothing : error("variant must be one of [pca, tsne]")
    dataset = Basicset(inpath)
    # so that only easy and medium anomalies are used if possible
    if (variant == "tsne") && 
    	(size(dataset.normal,2) + size(dataset.easy,2) + size(dataset.medium,2) + 
    	 	size(dataset.hard,2) + size(dataset.very_hard,2)) > max_samples
    	dataset = Basicset(dataset.normal, dataset.easy, dataset.medium, 
    		Array{Float,2}(undef,0,0),
    		Array{Float,2}(undef,0,0))
	end
    _dataset = dataset2D(dataset, variant, normalize, max_samples, perplexity)
    savetxt(_dataset, outpath)
    return _dataset
end

"""
	scatter_tsne(path)

Given a path with saved data, this will plot the first two dimensions of a dataset labeled
according to the anomaly detection classes.
"""
function scatter_tsne(path)
	data = Basicset(path)
	figure()
	title(basename(path))
	scatter(data.normal[1,:], data.normal[2,:], label = "normal", s= 5)
	for field in filter(x -> x != :normal, [f for f in fieldnames(typeof(data))])
        x = getfield(data,field)
        m = size(x,2)
        if m!= 0
            scatter(x[1,:],x[2,:],label=string(field), s= 5)
        end
    end
    legend()
end

"""
	multiclass_to_ad(data, labels, class)

Return the data matrix separated into a normal class and anomaly class,
where anomaly class is given by an id. Observations are rows of data.
"""
function multiclass_to_ad(data, labels::Array, class)
	normal = data[labels.!=class,:]
	anomalous = data[labels.==class,:]
	return normal, anomalous
end

"""
	multiclass_to_ad(inpath::String, outpath::String, data_cols_start, class_col; 

From a given inpath, it loads the data.csv file and creates N binary anomaly detection problems
in outpath.
"""
function multiclass_to_ad(inpath::String, outpath::String, data_cols_start, class_col; 
	data_cols_end = nothing, header=0,trans=false)
	infile = joinpath(inpath, "data.csv")
	df = CSV.File(infile, header = header) |> DataFrame
	N,M = size(df)
	dataset = basename(inpath)
 	# extract data
 	data_cols_end == nothing ? nothing : M = data_cols_end
 	X = convert(Array, df[data_cols_start:M])
 	trans ? X = transpose(X) : nothing
 	# extract class label
 	labels = df[class_col]
 	for class in unique(labels)
 		normal, anomalous = multiclass_to_ad(X, labels, class)
 		class_path = joinpath(outpath,"$(dataset)-$(class)")
 		mkpath(class_path)
 		fn = joinpath(class_path, "normal.txt")
 		fa = joinpath(class_path, "medium.txt")
 		writedlm(fn, normal)
 		writedlm(fa, anomalous)
 	end
 	return X, labels
end

function onehot(x::Vector)
	cats = unique(x)
	M = length(cats)
	N = length(x)
	res = fill(0,N,M)
	for (i,c) in enumerate(cats)
		res[x.==c,i] .= 1
	end
	return res
end

function onehot(X, id::Int)
	if any(size(X) .== 0)
		return Array{Float,2}(undef,0,0)
	else
		return cat(onehot(X[:,id]), X[:,1:size(X,2) .!= id], dims = 2)
	end
end

function onehot(path::String,id::Int)
	X, inds = cat(Basicset(path))
	X = transpose(X)
	Y = onehot(X,id)
	savetxt(uncat(transpose(Y),inds,true),path,false)
	return Y, size(Y,2) - size(X,2), inds
end
