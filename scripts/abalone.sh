DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
DATASET="abalone"
julia $DIR/../process_raw.jl $DATASET
echo "processed raw data, doing one-hot encoding and column labeling"
julia $DIR/../make_format.jl $DATASET 3
echo "processed, computing UMAP"
julia $DIR/../make_umap.jl $DATASET 10000  30 0.3 correlation
echo "done, if needed, dividing into multiple datasets"
julia $DIR/../postprocess_multiclass.jl $DATASET
echo "done, now creating UMAP plots"
julia $DIR/../make_plots.jl $DATASET
echo "Dataset $DATASET processed succesfuly!"
