# mq-protocol (P2)

**Status:** **shipped** — [`egao1980/mq-protocol`](https://github.com/egao1980/mq-protocol) OCI **0.1.0** (`stack-mq`) + [`mq-backend-amqp`](https://github.com/egao1980/mq-backend-amqp) **0.2.0** (RabbitMQ) + [`mq-backend-kafka`](https://github.com/egao1980/mq-backend-kafka) **0.2.1** (librdkafka). Live canary: [`mq-parity`](https://github.com/egao1980/mq-parity) **0.2.0** (RabbitMQ, Redpanda / Kafka through the backends' own transports).

CLOS message queues: `publish` / `poll-messages` / `ack` / `nack` (+ `subscribe`, transactions), `mq-message` (key, payload octets, headers, delivery tag, redelivered, exchange, topic), `mq-backend-capabilities`.

| Python | cl-stack |
|---|---|
| `pika.BlockingConnection(ConnectionParameters(host, 5672, "/", PlainCredentials(u, p)))` | `mq-backend-amqp:with-amqp-backend (b :host :port :user :password :vhost)` |
| `pika.URLParameters("amqps://u:p@host/vhost")` | `:url "amqps://…"` (TLS through cl-stack-ssl; an IPv6 host loses its brackets, as in pika) |
| `channel.queue_declare` / `exchange_declare` / `queue_bind` | `amqp-declare-queue` / `amqp-declare-exchange` / `amqp-bind-queue` (each waits for its `-Ok`) |
| `channel.basic_publish` / `basic_get` / `basic_ack` / `basic_nack` | `publish` / `poll-messages` / `ack` / `nack` |
| `confluent_kafka.Producer` + `Consumer({"group.id": g})` | `mq-backend-kafka:make-kafka-backend :bootstrap-servers :group-id :config` |
| `producer.flush()` / `consumer.commit(msg)` | `kafka-flush` / `ack` |

## Locked decisions

| Decision | Choice |
|----------|--------|
| **AMQP** | Pure Lisp 0-9-1: handshake (SASL PLAIN), negotiated heartbeats (no background thread; every call ticks, and a broker silent for two intervals fails the call with `amqp-transport-error`), full method table, broker `Close` → `amqp-connection-closed` / `amqp-channel-closed` with reply code and text; the channel reopens on next use |
| **AMQP delivery tags** | A broker channel close retires the tags handed out; `ack` / `nack` of a delivery that is not outstanding sends nothing and signals `amqp-stale-delivery` (reason `:channel-closed` / `:settled` / `:other-connection` / `:no-ack`; restart `continue`) |
| **Kafka** | librdkafka 2.16.0 as native overlays (linux amd64 / arm64, darwin arm64, windows amd64), loaded at ASDF load by asdf-native; consumer groups, `enable.auto.commit=false`, `ack` = synchronous offset commit, `nack :requeue t` = seek back |
| **Kafka rebalances** | The driver's own rebalance callback (eager and cooperative); an `ack` / `nack` of a message from a partition this member lost commits nothing and signals `kafka-partition-revoked` (restart `continue`) |
| **Kafka threads** | `poll-messages` polls in slices of at most 200 ms without holding the session lock, so `ack` and `publish` on other threads do not wait for it; `close` stops a poll in progress (0.2.1) |
| **Delivery** | at-least-once on both |
| **Push subscribe** | Not yet: AMQP keeps deliveries for `poll-messages` ([mq-backend-amqp#5](https://github.com/egao1980/mq-backend-amqp/issues/5)); the Kafka driver is pull only (`subscribe-p nil`) |
