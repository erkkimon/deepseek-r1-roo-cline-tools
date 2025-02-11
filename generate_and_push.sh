#!/bin/bash
set -euo pipefail

# Directory to store generated modelfiles.
OUTPUT_DIR="./generated_modelfiles"
mkdir -p "$OUTPUT_DIR"

# Template modelfile to modify.
TEMPLATE="modelfile_sample.modelfile"

# Define the model sizes.
sizes=("1.5b" "7b" "8b" "14b" "32b" "70b")

# Define the quantization variants.
# "vanilla" means no extra quantization suffix.
quant_variants=("vanilla" "q4_K_M" "q8_0")

# Define the context (num_ctx) values as strings.
ctx_values=("8k" "16k" "32k" "64k")
# Function to map a ctx value (like "8k") to its numeric equivalent.
get_numeric_ctx() {
    case "$1" in
        "8k") echo 8000 ;;
        "16k") echo 16000 ;;
        "32k") echo 32000 ;;
        "64k") echo 64000 ;;
        *) echo "Unknown ctx value: $1" >&2; exit 1 ;;
    esac
}

# Define the temperature variants.
temperatures=(0.1 0.2 0.3 0.4 0.5 0.6 0.7)

# Map a given model size and quant variant to the proper deepseek-r1 base model version.
get_base_model() {
    local size="$1"
    local quant="$2"
    if [ "$quant" == "vanilla" ]; then
        echo "$size"
    elif [ "$quant" == "q4_K_M" ]; then
        case "$size" in
            "1.5b") echo "1.5b-qwen-distill-q4_K_M" ;;
            "7b")   echo "7b-qwen-distill-q4_K_M" ;;
            "8b")   echo "8b-llama-distill-q4_K_M" ;;
            "14b")  echo "14b-qwen-distill-q4_K_M" ;;
            "32b")  echo "32b-qwen-distill-q4_K_M" ;;
            "70b")  echo "70b-llama-distill-q4_K_M" ;;
            *) echo "Unknown size for q4_K_M: $size" >&2; exit 1 ;;
        esac
    elif [ "$quant" == "q8_0" ]; then
        case "$size" in
            "1.5b") echo "1.5b-qwen-distill-q8_0" ;;
            "7b")   echo "7b-qwen-distill-q8_0" ;;
            "8b")   echo "8b-llama-distill-q8_0" ;;
            "14b")  echo "14b-qwen-distill-q8_0" ;;
            "32b")  echo "32b-qwen-distill-q8_0" ;;
            "70b")  echo "70b-llama-distill-q8_0" ;;
            *) echo "Unknown size for q8_0: $size" >&2; exit 1 ;;
        esac
    else
        echo "Unknown quant variant: $quant" >&2; exit 1
    fi
}

# Array to store tags for later removal.
tags=()

# Loop through each combination of size, quant variant, ctx, and temperature.
for size in "${sizes[@]}"; do
    for quant in "${quant_variants[@]}"; do
        base_model=$(get_base_model "$size" "$quant")
        
        # Build a quant indicator for tag and filename (empty for vanilla).
        if [ "$quant" == "vanilla" ]; then
            quant_indicator=""
        else
            quant_indicator="-$quant"
        fi
        
        for ctx in "${ctx_values[@]}"; do
            numeric_ctx=$(get_numeric_ctx "$ctx")
            # Create a context indicator (e.g. "8k_ctx").
            ctx_indicator="${ctx}_ctx"
            
            for temp in "${temperatures[@]}"; do
                # Build the output filename.
                # Example: deepseek-r1-roo-cline-tools-14b-q4_K_M-32k_ctx-temp0.6.modelfile
                file_name="deepseek-r1-roo-cline-tools-${size}${quant_indicator}-${ctx_indicator}-temp${temp}.modelfile"
                output_file="${OUTPUT_DIR}/${file_name}"
                
                # Build the ollama image tag.
                # Example: tom_himanen/deepseek-r1-roo-cline-tools:14b-q4_K_M-32k_ctx-temp0.6
                tag="tom_himanen/deepseek-r1-roo-cline-tools:${size}${quant_indicator}-${ctx_indicator}-temp${temp}"
                
                echo "---------------------------------------------------------"
                echo "Generating modelfile: ${output_file}"
                echo "  FROM line set to: FROM deepseek-r1:${base_model}"
                echo "  num_ctx set to: ${numeric_ctx}"
                echo "  temperature set to: ${temp}"
                
                # Modify the template:
                #   - Replace the FROM line.
                #   - Replace the num_ctx parameter.
                #   - Replace the temperature parameter.
                sed -e "s|^FROM .*|FROM deepseek-r1:${base_model}|" \
                    -e "s|^PARAMETER num_ctx .*|PARAMETER num_ctx ${numeric_ctx}|" \
                    -e "s|^PARAMETER temperature .*|PARAMETER temperature ${temp}|" \
                    "$TEMPLATE" > "$output_file"
                
                echo "Creating ollama image with tag: ${tag}"
                ollama create "$tag" -f "$output_file"
                
                echo "Pushing ollama image with tag: ${tag}"
                ollama push "$tag"
                
                # Save the tag for removal later.
                tags+=("$tag")
                echo "---------------------------------------------------------"
            done
        done
    done
done

echo "All images have been created and pushed successfully."

echo "Removing all created images locally using ollama rm..."
for tag in "${tags[@]}"; do
    echo "Removing image: ${tag}"
    ollama rm "$tag"
done

echo "All local model versions have been removed."

