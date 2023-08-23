#!/bin/bash

WEBSITE_URL='https://findaudiobook.net/'

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --out) OUTPUT_FOLDER="$2"; shift ;;  # if --out is found, shift the arguments and capture the next value
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

OUTPUT_FOLDER="${OUTPUT_FOLDER:-./books}"  # Set default value if not provided


strip_unwanted_chars() {
    echo "$1" | sed 's/[^a-zA-Z0-9 ,.!?-]//g'
}

create_folder_if_not_exists() {
    [ ! -d "$1" ] && mkdir -p "$1"
}

url_encode() {
    local length="${#1}"
    for (( i=0; i<$length; i++ )); do
        local c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9._~-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

trim() {
    local var="$*"
    # Remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

download_audio_files() {
    local audio_files="$1"
    local book_folder="$2"

    echo "$audio_files" | xargs -I {} -P 4 bash -c "filename=\$(echo '{}' | grep -oP '/\K\d+\.mp3'); curl -o '${book_folder}/'\$filename '{}' > /dev/null 2>&1"
}


download_book() {
    echo ""
    local name="$1"
    echo "searching for book '$name'"
    # Splitting by spaces, URL encoding, and joining with '+'
    local encoded_string=""
    for word in $name; do
        encoded_string+=$(url_encode "$word")+  # Append each encoded word followed by '+'
    done
    encoded_string=${encoded_string%+}  # Remove the trailing '+'

    local url="${WEBSITE_URL}?s=${encoded_string}"

    local html_string=$(curl -s "$url")

    local first_article=$(echo "$html_string" | awk '/<article id="[^"]*" class="[^"]*post[^"]*">/,/<\/article>/ {print; if ($0 ~ /<\/article>/) exit}')

    if [[ -z "$first_article" ]]; then
        echo "no articles found for '$name'"
        return
    fi

    local first_article_title_link_text=$(echo "$first_article" | grep -oP 'rel="bookmark">\K(.*)(?=Audiobook \(Online\)<)')
    first_article_title_link_text=$(echo "$first_article_title_link_text" | sed 's/&#8211;/-/g')
    first_article_title_link_text=$(trim "$first_article_title_link_text")

    local lowercase_name=${name,,}
    local lowercase_first_article=${first_article_title_link_text,,}

    if [[ "$lowercase_first_article" != *"$lowercase_name"* ]]; then
        echo "bould not find book with name '$name'"
        return
    fi

    local safe_book_name=$(echo "$first_article_title_link_text" | sed 's/[^a-zA-Z0-9-]/_/g' | sed 's/__/_/g' | sed 's/_-_/-/g')
    echo "book name is '$safe_book_name'"

    local audio_files=$(echo "$first_article" | grep -oP '<source type="audio/mpeg" src="\K(.*)(?=" )')
    # print how many files were found
    echo "found $(echo "$audio_files" | wc -l) audio files"

    local book_folder="${OUTPUT_FOLDER}/${safe_book_name}"
    create_folder_if_not_exists "$book_folder"

    download_audio_files "$audio_files" "$book_folder"

    echo "downloaded"
}

main() {
    # Read from stdin into an array
    mapfile -t books_to_download
    if [ "${#books_to_download[@]}" -eq 0 ]; then
        echo "No books to download"
        exit 0
    fi

    for book in "${books_to_download[@]}"; do
        book=$(strip_unwanted_chars "$book")
        download_book "$book"
    done
}

main "$@"
