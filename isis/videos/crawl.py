''' Script to scrape http://jihadology.net for ISIS related videos '''
# Author: Travis G. Coan
# Date: 12/1/15
# Version: 0.01

# Dependencies
import time
from selenium import webdriver
from selenium.webdriver.chrome.options import Options # pass options to driver
import re
import json
import dateparser # easily parse dates
from operator import itemgetter, attrgetter, methodcaller
import urllib
import unicodecsv as csv
import operator

def drop_dups(posts, idx):
    seen = set()
    seen_add = seen.add
    return [ x for x in posts if x[idx] not in seen and not seen_add(x[idx])]

def _extract_video_url(content):
    try:
        iframe = content.find_element_by_tag_name('iframe')
        video_url = iframe.get_attribute('src')
        # Check if the URL points to a widget
        if re.search(r'widgets.wp.com', video_url) != None:
            video_url = 'NA'
    except:
        video_url = 'NA'
    return video_url

def _extract_title(article):
    try:
        entry_title = article.find_element_by_class_name('entry-title')
        title = entry_title.text
    except:
        title = "Missing"
    return title

def _extract_entry_url(article):
    try:
        entry_url = article.find_element_by_class_name('entry-title').find_element_by_tag_name('a').get_attribute('href')
    except:
        entry_url = "Missing"
    return entry_url

def _extract_date(article):
    try:
        date = article.find_element_by_class_name('entry-date').find_element_by_tag_name('a').text
    except:
        date = "Missing"
    return date

def extract_meta_data(article):

    # Extract meta data
    title = _extract_title(article)
    entry_url = _extract_entry_url(article)
    date = _extract_date(article)

    # Extract the video URL
    try:
        content = article.find_element_by_class_name('entry-content')
        video_url = _extract_video_url(content)
    except:
        print "entry-content object is missing."
        video_url = "Missing"

    return({'date': date, 'title': title, 'entry_url': entry_url, 'video_url': video_url})

def check_load_more(driver):
    try:
        # Check for "Load More" button
        driver.find_element_by_xpath('//*[@id="infinite-handle"]')
        return True
    except:
        return False

def next_page(driver, root_url, page_count):
    page_count += 1
    page_url = root_url + "/page/%s/" % page_count
    return (page_url, page_count)

def scrape(start_url):
    # Scrape while a "Load More" button is present
    posts_content = []
    page_count = 1 # Initialize start page
    load_more = True
    driver.get(start_url)
    time.sleep(1)
    while load_more:
        # Find articles for page
        try:
            posts = driver.find_element_by_xpath('//*[@id="posts-container"]')
            articles = posts.find_elements_by_tag_name('article')

            # Extract meta data for each article
            for article in articles:
                posts_content.append(extract_meta_data(article))

            # Move to the next page
            load_more = check_load_more(driver)
            if load_more:
                page_url,page_count = next_page(driver, start_url, page_count)
                driver.get(page_url)
            else:
                print 'Cannot find the "Load More" element. \nroot_url = %s \npage_count = %s' % (start_url, str(page_count))
        except:
            posts_content = "Missing"
            load_more = False

    return posts_content

def get_video_src(driver):
    video = driver.find_element_by_tag_name('video')
    video_src = video.get_attribute('src')
    return video_src

def download_video(id, video_src, root_path):
    # Download video
    file_name = root_path + "/video%s.mp4" % id
    downloader = urllib.FancyURLopener()
    print "Starting download..."
    downloader.retrieve(video_src, file_name)
    print "Download finished..."
    print "File written to " + file_name

def main(start_urls):
    scrape_content = []
    for start_url in start_urls:
        content = scrape(start_url)
        scrape_content.append({'category': start_url, 'content': content})
    return scrape_content


# ----------------------------------------------------------------------------
# Scrape video meta-data and paths to video content

# Initialize driver. You will need to change to update the path_to_driver
# variable to point to where the Chrome webdriver lives on your machine.
path_to_driver = "INSERT PATH TO CHROME DRIVER"
chrome_options = Options()
user_agent = "user-agent=Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_8; en-US) AppleWebKit/532.2 (KHTML, like Gecko) Chrome/4.0.222.5 Safari/532.2"
chrome_options.add_argument(user_agent)
driver = webdriver.Chrome(path_to_driver, chrome_options=chrome_options)

# Read start URLs
start_path = 'start_urls.csv'
with open(start_path, 'r') as csvfile:
    csvreader = csv.reader(csvfile, encoding = 'utf-8')
    start_urls = [row[0] for row in csvreader]

# Scrape
scrape_content = []
for start_url in start_urls:
    content = scrape(start_url)
    scrape_content.append({'category': start_url, 'content': content})

# Write to JSON file to disk
path = 'jihadology.json'
with open(path, 'w') as jfile:
    json.dump(scrape_content, jfile, indent=4)

#------------------------------------------------------------------------------
# Prepare meta-data

# Make rectangular and write as a CSV
data = []
catid = 0
counter = 1
for row in scrape_content:
    category = row['category']
    catid += 1
    for el in row['content']:
        if row['content'] != 'Missing':
            data.append([counter, catid, category, el['date'], el['entry_url'], el['title'], el['video_url']])
            counter += 1

# Sort list in decending prior to removing duplicates
data_sorted = sorted(data, key = operator.itemgetter(1, 0), reverse = True)

# Write CSV to disk
data_no_dups = drop_dups(data_sorted, 4) # remove duplicates
path = 'jihadology.csv'
with open(path, 'w') as csvfile:
    csvwriter = csv.writer(csvfile, encoding = 'utf-8')
    csvwriter.writerows(data_no_dups)

# Write rows with video content
videos = [row for row in data_no_dups if row[6] != 'NA']
path = 'jihadology_videos.csv'
with open(path, 'w') as csvfile:
    csvwriter = csv.writer(csvfile, encoding = 'utf-8')
    csvwriter.writerows(videos)

# ----------------------------------------------------------------------------
# Download videos

# Update the path_to_videos variable to where you would like to save the
# the downloaded videos.
path_to_videos = 'UPDATE PATH'
for video in videos:
    driver.get(video[-1])
    time.sleep(1)
    try:
        video_src = get_video_src(driver)
        download_video(video[0], video_src, root_path)
    except:
        print "Failed to download the following video..."
        print video
    time.sleep(1)
