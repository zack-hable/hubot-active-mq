# Hubot Active MQ Plugin

Active MQ integration for Hubot with multiple server support.

### Installation

In hubot project repo, run:

`npm install git+https://github.com/zack-hable/hubot-active-mq --save`

Then add **hubot-active-mq** to your `external-scripts.json`:

```json
[
  "hubot-active-mq"
]
```


### Configuration
Auth should be in the "user:password" format.\

- ```HUBOT_ACTIVE_MQ_URL```
- ```HUBOT_ACTIVE_MQ_AUTH```
- ```HUBOT_ACTIVE_MQ_BROKER```
- ```HUBOT_ACTIVE_MQ_{1-N}_URL```
- ```HUBOT_ACTIVE_MQ_{1-N}_AUTH```
- ```HUBOT_ACTIVE_MQ_{1-N}_BROKER```

### Commands
- ```hubot mq list``` - lists all queues
- ```hubot mq stats <queueName>``` - retrieves stats  for given queue
- ```hubot mq s <queueNumber>``` - retrieves stats  for given queue
- ```hubot mq stats``` - retrieves stats for broker
- ```hubot mq queue stats``` - retrieves stats for all queues
- ```hubot mq servers``` - lists all servers and queues attached to them.
- ```hubot mq alert list``` - list all alerts and their statuses
- ```hubot mq alert start <AlertNumber>``` - starts given alert.  use alert list to get id
- ```hubot mq alert start``` - starts all alerts
- ```hubot mq alert stop <AlertNumber>``` - stops given alert.  use alert list to get id
- ```hubot mq alert stop``` - stops all alerts
- ```hubot mq check <QueueName> every <X> <days|hours|minutes|seconds> and alert me when <queue size|consumer count> is (>|<|=|<=|>=|!=|<>) <Threshold>``` - Creates an alert that checks <QueueName> at time interval specified for conditions specified and alerts when conditions are met
- ```hubot mq check broker stats on <server> every <X> <days|hours|minutes|seconds> and alert me when <store percent|memory percent> is (>|<|=|<=|>=|!=|<>) <Threshold>``` - Creates an alert that checks broker stats at time interval specified for conditions specified and alerts when conditions are met

**NOTE: Alerts are currently dependent on the use of a channel id to send alerts (this is due to having to persist the data) and is currently supported with the Slack adapter**

### Persistence
Note: Various features will work best if the Hubot brain is configured to be persisted. By default
the brain is an in-memory key/value store, but it can easily be configured to be persisted with Redis so
data isn't lost when the process is restarted.

@See [Hubot Scripting](https://hubot.github.com/docs/scripting/) for more details
