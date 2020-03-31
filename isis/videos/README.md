# Videos from https://jihadology.net

### Summary

This repository provides the code used to crawl https://jihadology.net and download the relevant videos. The code was written in Python 2.7 and is quite old. You will likely need to update the code to reflect changes to https://jihadology.net. However, we are publishing the code here on the off chance that it will be helpful in this update or in getting started with using Selenium.

Note that crawl.py script requires Python bindings for [Selenium](https://selenium-python.readthedocs.io/) and a [Chrome WebDriver](https://chromedriver.chromium.org/).

### Contents

We provide the relevant data and code in two subdirectories:

* **crawl.py**: This script uses Selenium and a Chrome WebDriver to scrape relevant meta-data for each video entry on https://jihadology.net and downloads the video content to a local directory.
* **start_urls.csv**: These are URLs used to start the crawl.
* **video_metadata.csv**: A CSV file holding the meta data captured during the crawl.
