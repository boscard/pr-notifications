# pr-notifications
## About
This script is for notifying you about PRs waiting review on GitHub. It is able to use one of two methods of notyfications:
* system notifications using notify-send
* rocketChat channel message
## Setup
1. Create configuration file
   ```
   mkdir -p ~/.config/pr-notifier/
   cat > ~/.config/pr-notifier/vars <<EOF
   githubToken=<here you have to place your GitHub token>
   notificationMethod=<"rocketChat" or "notify-send">
   rocketChatWebhookURL='<here you have to place rocketChat webhook url generated in rocketChat>'
   rcChanelName='<"#" before channel name or "@" before user name>'
   ```
1. Copy script
   `sudo cp pr-notifications.sh /usr/local/bin/pr-notifications.sh`
1. Copy systemd config files
   `sudo cp pr-notifications@.* /etc/systemd/system/`
1. Enable and start services
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable pr-notifications@$(whoami).service
   sudo systemctl enable pr-notifications@$(whoami).timer
   sudo systemctl start pr-notifications@$(whoami).service
   sudo systemctl start pr-notifications@$(whoami).timer
   ```
