# Hubot Active MQ Plugin

Active MQ integration for Hubot with multiple server support.

### Installation

In hubot project repo, run:

`npm install git+https://github.com/zack-hable/hubot-active-mq --save`

Then add **hubot-jenkins-enhanced-improved** to your `external-scripts.json`:

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

### Commands
- ```hubot mq list``` - lists all queues
- ```hubot mq describe <queueName>``` - retrieves information for given queue
- ```hubot mq d <queueNumber>``` - retrieves information for given queue
- ```hubot mq stats``` - retrieves stats for broker
- ```hubot mq s``` - retrieves stats for broker

### Persistence **
Note: Various features will work best if the Hubot brain is configured to be persisted. By default
the brain is an in-memory key/value store, but it can easily be configured to be persisted with Redis so
data isn't lost when the process is restarted.

@See [Hubot Scripting](https://hubot.github.com/docs/scripting/) for more details
