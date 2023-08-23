import os
import re
import argparse
import sys

import requests
from multiprocessing.pool import ThreadPool

WEBSITE_URL = 'https://findaudiobook.net/'

# Parsing command-line arguments
parser = argparse.ArgumentParser()
parser.add_argument('--output', default='./books', help="Output directory for downloaded books")
parser.add_argument('--file', default=None, type=str,
                    help="Path to the book list file where each line is a book name", nargs='?')
args = parser.parse_args()

OUTPUT_FOLDER = args.output_dir


def strip_unwanted_chars(text):
    # Retains alphanumeric, spaces, and common punctuation
    return re.sub(r'[^a-zA-Z0-9 ,.!?-]', '', text)


books_to_download = []

# Check if stdin has content
if not sys.stdin.isatty():
    books_to_download = [strip_unwanted_chars(line) for line in sys.stdin.readlines()]

# Check if book_list argument is provided
elif args.book_list:
    print(f"reading books from {args.book_list}")
    with open(args.book_list, 'r') as f:
        books_to_download = [strip_unwanted_chars(line) for line in f.readlines()]


def create_folder_if_not_exists(path):
    if not os.path.exists(path):
        os.makedirs(path)


def download_file(job):
    response = requests.get(job['url'], stream=True)
    with open(job['path'], 'wb') as file:
        for chunk in response.iter_content(chunk_size=8192):
            file.write(chunk)


def download_multiple_files(jobs):
    ThreadPool(8).map(download_file, jobs)


def download_book(name):
    print()
    print(f'searching for "{name}"')
    url = f"{WEBSITE_URL}?s={'+'.join(map(lambda word: requests.utils.quote(word), name.split(' ')))}"

    response = requests.get(url)
    html_string = response.text

    first_article = re\
        .search(r'<article id="[^"]*" class="[^"]*post[^"]*">(?:[\s\S]*?)<\/article>', html_string)\
        .group(0)

    # find text that looks like this rel="bookmark">.*Audiobook \(Online\)< but take only the .* part
    first_article_title_link_text = re.search(r'rel="bookmark">(.*)Audiobook \(Online\)<', first_article).group(1)
    first_article_title_link_text = re.sub(r"&#8211;", "-", first_article_title_link_text)

    if not name.lower() in first_article_title_link_text.lower():
        print(f"Could not find book with name {name}")
        return

    safe_book_name = re.sub(
        r"[^a-zA-Z0-9-]",
        "_",
        first_article_title_link_text.replace('(Online)', '')
        .replace('Audiobook', '')
        .strip()
    )
    safe_book_name = re.sub(r"_{2,}", "_", safe_book_name)
    safe_book_name = re.sub(r"_-_", "-", safe_book_name)
    print(f'  book name is "{safe_book_name}"')

    audio_files = re.findall(r'<source type="audio/mpeg" src="(.*)" ', first_article)
    print(f"  downloading {len(audio_files)} audio files")

    book_folder = os.path.join(OUTPUT_FOLDER, safe_book_name)
    create_folder_if_not_exists(book_folder)

    jobs = [{
        "url": audio_file,
        "path": os.path.join(book_folder, re.search(r"/(\d+\.mp3)", audio_file).group(1)),
    } for audio_file in audio_files]
    download_multiple_files(jobs)


def main():
    if not books_to_download:
        print("no books to download")
        exit(0)

    print(f"downloading {len(books_to_download)} books")
    print(f"output folder is {OUTPUT_FOLDER}")
    create_folder_if_not_exists(OUTPUT_FOLDER)

    for book in books_to_download:
        download_book(book)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("exiting...")
        exit(0)
