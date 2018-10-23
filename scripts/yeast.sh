DATASET="yeast"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
julia $DIR/../process_raw.jl $DATASET 2 10 9
echo "processed raw data, doing one-hot encoding and column labeling"
julia $DIR/../make_onehot_and_format.jl $DATASET
echo "processed, computing UMAP"
julia $DIR/../make_umap.jl $DATASET 10000
echo "done, if needed, dividing into multiple datasets"
julia $DIR/../postprocess_multiclass.jl $DATASET
echo "done, now creating UMAP plots"
julia $DIR/../make_plots.jl $DATASET 2 0.3
echo "Dataset $DATASET processed succesfuly!"