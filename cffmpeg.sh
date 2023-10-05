#!/bin/bash

# =================== CONFIG =================== #

# Must be below 0
# -50 is low, -5 is high, 0 is maximum, mean is -20
invalid_ext='sh txt ini xspf'
zoomtime=300

# =================== SYSTEM =================== #

base_codec='-c:v copy'

# ===================  CODE  =================== #

while [ -n "$1" ]
do
    case "$1" in
        --volume)
            mean_volume="$2"
            shift
            ;;
        --force) ;&
        -f)
            force=true
            ;;
    --start) ;&
    -s)
        start='-ss '"$2"
        shift
        ;;
    --duration) ;&
    -d)
        duration='-t '"$2"
        shift
        ;;
    --output) ;&
    -o)
        output_file="$2"
        shift
        ;;
    -v) ;&
    --verbose)
        verbose=true
        ;;
    --re-encode) ;&
    -r)
        reload=true
        ;;
    -z) ;&
    --zoom)
        zoom=true
        ;;
    --zoom-time)
        zoomtime="$2"
        shift
        ;;
    -c) ;&
    --concat)
        concat=true
        ;;
    *)
            files=("${files[@]}" "$1")
            ;;
    esac
    shift
done

if [ -z "$files" ]; then
    echo "No files given"
    exit 1
fi

move=false
skipped=0
invalid_ext=$(echo $invalid_ext | sed -E 's/\ /|/g')
if [[ $concat = true ]]; then
    input=""
    va=""
    for ((i = 0; i < ${#files[@]}; i++)); do
        file="${files[$i]}"
        input="$input""-i $file "
        va="$va""[$i:v] "
    done
    echo ffmpeg "${input::-1} -filter_complex '${va::-1} concat=n=$i:v=1:a=1 [v] [a]' -map '[v]' -map '[a]' $output_file"
else
    for ((i = 0; i < ${#files[@]}; i++))
    do
        codec="$base_codec"
        file="${files[$i]}"
        output="$output_file"
        if [ -f "$file" ]; then
            file_extension=$(echo $file | sed -E 's/.*\.(.*)/\1/')
            if [[ -n "$file_extension" && ! "$file_extension" =~ ^($invalid_ext)$ ]]; then
                if [[ -z "$output" ]]; then
                    output=$file
                # output is directory
                elif [[ "$output" == */ ]] || [[ -d "$output" ]]; then
                    if [[ "$output" != */ ]]; then
                        output="$output"/
                    elif [[ -e "$output" ]]; then
                        echo "Invalid output, file $output exists."
                        continue
                    else
                        mkdir -p output
                    fi
                    output="$output$file"
                elif [[ "$output" == .* ]]; then
                    output="%file$output"
                fi
                file_no_ext=$(echo $file | sed -E 's/(.*)\..*/\1/')
                output=${output//%file/"$file_no_ext"}
                extension=$(echo $output | sed -E 's/.*\.(.*)/\1/')
                if [[ "$file_extension" != "$extension" || $reload = true ]]; then
                    codec=''
                fi

                if [[ -f "$output" && $force = true ]]; then
                    temp_output="$(echo $output | sed -E 's/(.*)\..*/\1/')"$(mktemp -u tmp-XXXXXX)".$extension"
                    printf "Processing %s... " "$output"
                elif [[ -f "$output" ]]; then
                    (( ++skipped ))
                    continue
                else
                    printf "Converting %s to %s... " "$file" "$output"
                fi

                if [[ ! -z "$mean_volume" ]]; then
                    increase=$(bc -l <<< "e(l(10)*(($mean_volume-($(ffmpeg -i "$file" -af "volumedetect" -vn -sn -dn -f null /dev/null 2>&1 | grep -o "mean_volume.*dB" | sed -E "s/mean_volume: (.*) dB/\1/")))/20))")
                    printf "Increasing volume by %.2f... " "$increase"
                fi
                printf '\n'
                if [[ -z "$temp_output" ]]; then
                    out="$output"
                else
                    out="$temp_output"
                fi
                if [[ $zoom = true ]]; then
                    ffmpeg -loop 1 -i "$file" -y -filter_complex '[0]scale=-1:1080,setsar=1:1[out];[out]scale=8000:-1,zoompan=z=zoom+0.001:x=iw/2-(iw/zoom/2):y=ih/2-(ih/zoom/2):d='"$zoomtime"':fps=30[out]' -acodec aac -vcodec libx264 -map [out] -map '0:a?' -pix_fmt yuv420p -r 30 $duration "$out"
                else
                    if [[ $verbose = true ]]; then
                        ffmpeg -y -i "$file" $start $duration -filter:a volume=$increase $codec "$out"
                    else
                        ffmpeg -y -i "$file" $start $duration -filter:a volume=$increase $codec "$out" 2>/dev/null
                    fi
                fi
                if [[ ! -z "$temp_output" ]]; then
                    mv "$temp_output" "$output"
                fi
            fi
        else
            echo 'File '"$file"' not found'
        fi
    done

    if [ $skipped -ne 0 ]; then
        echo "$skipped files was skipped as they already exist. Use --force or -f to overwrite"
    fi
fi
