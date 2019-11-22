#!/bin/bash 
set -eo pipefail

token=$1
fullReminder=$2
sqlite3DbPath=$3

function executeCurl() {

        CURL_OUT_TMP=$(mktemp)
        retCode=$(curl "${@}" -w '%{http_code}' -o ${CURL_OUT_TMP})
        if [ $retCode -lt 400 ]
        then
                cat "${CURL_OUT_TMP}"
        else
                cat "${CURL_OUT_TMP}" >&2
                exit 4
        fi
	rm ${CURL_OUT_TMP}
}

if [ -z "$sqlite3DbPath" ]
then
	# Using defautl db in .config/pr-notifier/data.db
	sqlite3DbPath="${HOME}/.config/pr-notifier/data.db"
fi

if [ -z "$fullReminder" ]
then
	fullReminder=86400
fi

if [ -z "$token" ]
then
	echo "No GitHub token!"
	exit 1
fi

# Create empty db if not present
if [ ! -d "$(dirname $sqlite3DbPath)" ]
then
	mkdir -p "$(dirname $sqlite3DbPath)" || (echo "Cannot create dirrectory for DB: $(dirname $sqlite3DbPath)"; exit 2)
fi

if [ ! -f "$sqlite3DbPath" ]
then
	sqlite3 "$sqlite3DbPath" "CREATE TABLE prs ( html_url TEXT PRIMARY KEY, title TEXT, id INTEGER);" || (echo "Cannot create database!"; exit 3)
	sqlite3 "$sqlite3DbPath" "CREATE TABLE config ( full_reminder_last_executed_at INTEGER);" || (echo "Cannot create database!"; exit 3)
	sqlite3 "$sqlite3DbPath" "INSERT INTO config ( full_reminder_last_executed_at ) VALUES ( 0 )"
fi

# get timestamp for calculation
currentTS=$(date +%s)

# get user login
userLogin=$(executeCurl -s -L -u $token https://api.github.com/user | jq -r '.login')

pendingPRs=0
# get pr's
oldIFS=$IFS
IFS=$'\n'
for dataLine in $(executeCurl -s -L -u $token "https://api.github.com/search/issues?q=is:open+is:pr+review-requested:${userLogin}" | jq -r '.items[] | "\(.id);\(.html_url);\(.title)"')
do
	pendingPRs=$((pendingPRs + 1))
	pr_id=$(echo $dataLine | awk -F ';' '{print $1}')
	html_link=$(echo $dataLine | awk -F ';' '{print $2}')
	title=$(echo $dataLine | awk -F ';' '{print $3}')
	if [ $(sqlite3 "$sqlite3DbPath" "SELECT COUNT(*) FROM prs WHERE id=${pr_id}") -eq 0 ]
	then
		sqlite3 "$sqlite3DbPath" "INSERT INTO prs (id,html_url,title) VALUES ('${pr_id}','${html_link}','${title}')"
		notify-send 'New PR needs yours attention!' "There is new PR waiting for you :)\n\t${title}\n\t${html_link}" --icon=dialog-information
	fi
done
IFS=$oldIFS

lastNotificationDate=$(sqlite3 "$sqlite3DbPath" "SELECT full_reminder_last_executed_at FROM config" )
if [ $((currentTS - lastNotificationDate)) -gt $fullReminder ]
then
	sqlite3 "$sqlite3DbPath" "UPDATE config SET full_reminder_last_executed_at=${currentTS}"
	notify-send "Some PR's are waiting for review!" "They are ${pendingPRs} waiting for your review! Please check them :)" --icon=dialog-information
fi
