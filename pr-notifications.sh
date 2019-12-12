#!/bin/bash -x
set -eo pipefail

configFile="${1:-$HOME/.config/pr-notifier/vars}"

if [ -f "$configFile" ]
then
	source $configFile
else
	echo "No config file!"
	exit 1
fi

sqlite3DbPath="${databasePath:-$HOME/.config/pr-notifier/data.db}"
fullReminder=${fullReminderPeriod:-86400}
prNotificationMethod="${notificationMethod:-notify-send}"

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

function checkDependencies() {
	requirementsToCheck="sqlite3
				curl
				notify-send
				jq
				awk"

	for requirement in $requirementsToCheck
	do
		which $requirement > /dev/null || (echo "I can't find : ${requirement} : - Aborting"; exit 5)
	done
}

function notifyNotifySend() {
	if [ ! -z "${4}" ]
	then
		notify-send "${1}" "<p>${2}<br/><a href='${3}'>${4}</a></p>" --icon=dialog-information
	else
		notify-send "${1}" "${2}" --icon=dialog-information
	fi
}

function notifyRocketChat() {
	if [[ (! -z "$rocketChatWebhookURL") && (! -z "$rcChanelName") ]]
	then
		if [ ! -z "${4}" ]
		then
			executeCurl -s -L -X POST -H 'Content-Type: application/json' -d "{\"text\":\"${2}: ${3} - ${4}\",\"channel\": \"${rcChanelName}\"}" ${rocketChatWebhookURL}
		else
			executeCurl -s -L -X POST -H 'Content-Type: application/json' -d "{\"text\":\"${2}\",\"channel\": \"${rcChanelName}\"}" ${rocketChatWebhookURL}
		fi
	else
		echo "Too less informations about rocketChat"
		exit 4
	fi
}

function notify() {
	case $prNotificationMethod in
		"notify-send")
			notifyNotifySend "${1}" "${2}" "${3}" "${4}"
			;;
		"rocketChat")
			notifyRocketChat "${1}" "${2}" "${3}" "${4}"
			;;
		*)
			echo "Why are you doing this? :("
			exit 5
	esac
}

if [ -z "$githubToken" ]
then
	echo "No GitHub token!"
	exit 1
fi

checkDependencies

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
userLogin=$(executeCurl -s -L -u "${githubToken}:" https://api.github.com/user | jq -r '.login')

pendingPRs=0
# get pr's
oldIFS=$IFS
IFS=$'\n'
for dataLine in $(executeCurl -s -L -u "${githubToken}:" "https://api.github.com/search/issues?q=is:open+is:pr+review-requested:${userLogin}" | jq -r '.items[] | "\(.id);\(.html_url);\(.title)"')
do
	pendingPRs=$((pendingPRs + 1))
	pr_id=$(echo $dataLine | awk -F ';' '{print $1}')
	html_link=$(echo $dataLine | awk -F ';' '{print $2}')
	title=$(echo $dataLine | awk -F ';' '{print $3}')
	if [ $(sqlite3 "$sqlite3DbPath" "SELECT COUNT(*) FROM prs WHERE id=${pr_id}") -eq 0 ]
	then
		sqlite3 "$sqlite3DbPath" "INSERT INTO prs (id,html_url,title) VALUES ('${pr_id}','${html_link}','${title}')"
		notify 'New PR needs yours attention!' 'There is new PR waiting for you :)' ${html_link} ${title}
	fi
done
IFS=$oldIFS

lastNotificationDate=$(sqlite3 "$sqlite3DbPath" "SELECT full_reminder_last_executed_at FROM config" )
if [ $((currentTS - lastNotificationDate)) -gt $fullReminder ]
then
	sqlite3 "$sqlite3DbPath" "UPDATE config SET full_reminder_last_executed_at=${currentTS}"
	message="They are ${pendingPRs} waiting for your review. Please check them :)"
	notify 'Some PRs are waiting for review!' "${message}"
fi
