## Module Description

This module implements [XEP-0313: Message Archive Management](https://xmpp.org/extensions/xep-0313.html).
It enables a service to store all user messages for one-to-one chats as well as group chats (MUC, MultiUser Chat).
It uses [XEP-0059: Result Set Management](http://xmpp.org/extensions/xep-0059.html) for paging.
It is a highly customizable module, that requires some skill and knowledge to operate properly and efficiently.

MongooseIM is compatible with MAM 0.4-0.6.

Configure MAM with different storage backends:

* RDBMS (databases like MySQL, PostgreSQL, MS SQL Server)
* Riak KV (NoSQL)
* Cassandra (NoSQL)
* ElasticSearch (NoSQL)

`mod_mam_meta` is a meta-module that ensures all relevant `mod_mam_*` modules are loaded and properly configured.

### Message retraction
This module supports [XEP-0424: Message Retraction](http://xmpp.org/extensions/xep-0424.html) with RDBMS storage backends. When a [retraction message](https://xmpp.org/extensions/xep-0424.html#example-4) is received, the MAM module finds the message to retract and replaces it with a tombstone.

The following criteria are used to find the original message:

* The `id` attribute specified in the `apply-to` element of the retraction message has to be the same as the `id` attribute of the `origin-id` (or `stanza-id` when configured, see [below](#retraction-on-the-stanza-id)) element of the original message.
* Both messages need to originate from the same user.
* Both messages need to be addressed to the same user.

If more than one message matches the criteria, only the most recent one is retracted. To avoid this case, it is recommended to use a unique identifier (UUID) as the origin ID.

#### Retraction on the stanza-id
This module also implements an extension to the XEP, where it allows to specify the [`stanza-id`](https://xmpp.org/extensions/xep-0359.html#stanza-id) as [created by](https://xmpp.org/extensions/xep-0313.html#archives_id) the server's MAM, instead of the `origin-id` that the original [XEP-0424](https://xmpp.org/extensions/xep-0424.html) specifies. It announces this capability under the namespace `urn:esl:message-retract-by-stanza-id:0`. This is specially useful in groupchats where the `stanza-id` of a message is shared and known for all participants.

In this case, to use such functionality,
```xml
<apply-to id="origin-id-1" xmlns="urn:xmpp:fasten:0">
  <retract xmlns='urn:xmpp:message-retract:0'/>
</apply-to>
```
turns into
```xml
<apply-to id="stanza-id-1" xmlns="urn:xmpp:fasten:0">
  <retract xmlns='urn:esl:message-retract-by-stanza-id:0'/>
</apply-to>
```
and likewise, the answer would be tagged by the mentioned `esl` namespace.

### Full Text Search
This module allows message filtering by their text body (if enabled, see *Common backend options*).
This means that an XMPP client, while requesting messages from the archive may not only specify standard form fields (`with`, `start`, `end`), but also `full-text-search` (of type `text-single`).
If this happens, the client will receive only messages that contain words specified in the request.

The exact behaviour, like whether word ordering matters, may depend on the storage backend in use.
For now `rdbms` backend has very limited support for this feature, while `cassandra` does not support it at all.
`riak` and `elasticsearch` backends, on the other hand, should provide you with the best results when it comes to text filtering.

`mod_mam_rdbms_arch` returns all messages that contain all search words, order
of words does not matter. Messages are sorted by timestamp (not by relevance).

#### Note on full text search with ElasticSearch backend

When using ElasticSearch MAM backend, the value provided in `full-text-search` form field will be passed to ElasticSearch as [Simple Search Query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-simple-query-string-query.html).
If you're using our official ElasticSearch mappings from `priv/elasticsearch` then the query analyzer is set to `english`.
Also note that the default separator for the search query is `AND` (which roughly means that ElasticSearch will search for messages containing all the terms provided in the query string).

## Options

### `modules.mod_mam_meta.backend`
* **Syntax:** string, one of `"rdbms"`, `"riak"`, `"cassandra"` and `"elasticsearch"`
* **Default:** `"rdbms"`
* **Example:** `backend = "riak"`

Database backend to use.

### `modules.mod_mam_meta.no_stanzaid_element`
* **Syntax:** boolean
* **Default:** `false`
* **Example:** `no_stanzaid_element = true`

Do not add a `<stanza-id/>` element from MAM v0.6.

### `modules.mod_mam_meta.is_archivable_message`
* **Syntax:** non-empty string
* **Default:** `"mod_mam_utils"`
* **Example:** `is_archivable_message = "mod_mam_utils"`

Name of a module implementing [`is_archivable_message/3` callback](#is_archivable_message) that determines if the message should be archived.

### `modules.mod_mam_meta.send_message`
* **Syntax:** non-empty string
* **Default:** `"mod_mam_utils"`
* **Example:** `send_message = "mod_mam_utils"`

Name of a module implementing `send_message/4` callback that routes a message during lookup operation.
Consult with `mod_mam_utils:send_message/4` code for more information.

Check `big_tests/tests/mam_send_message_SUITE_data/mam_send_message_example.erl` file
in the MongooseIM repository for the usage example.

### `modules.mod_mam_meta.archive_chat_markers`
* **Syntax:** boolean
* **Default:** `false`
* **Example:** `archive_chat_markers = true`

If set to true, XEP-0333 chat markers will be archived.
See more details [here](#archiving-chat-markers).

### `modules.mod_mam_meta.message_retraction`
* **Syntax:** boolean
* **Default:** `true`
* **Example:** `message_retraction = false`

Enables [XEP-0424: Message Retraction](http://xmpp.org/extensions/xep-0424.html).
This functionality is currently implemented only for the `rdbms` backend.
[Retraction messages](https://xmpp.org/extensions/xep-0424.html#example-4) are always archived regardless of this option.

**backend**, **no_stanzaid_element**, **is_archivable_message** and **message_retraction** will be applied to both `pm` and `muc` (if they are enabled), unless overridden explicitly (see example below).

### Enable one-to-one message archive

Archive for one-to-one messages can be enabled in one of two ways:

* Specify `[mod_mam_meta.pm]` section

```toml
[modules.mod_mam_meta]
[modules.mod_mam_meta.pm] # defining this section enables PM support
```

* Define any PM related option

```toml
[modules.mod_mam_meta]
  pm.backend = "rdbms" # enables PM support and overrides its backend
```

### Disable one-to-one message archive

To disable archive for one-to-one messages please remove PM section or any PM related option from the config file.

### PM-specific options

#### `modules.mod_mam_meta.pm.archive_groupchats`
* **Syntax:** boolean
* **Default:** `false`
* **Example:** `modules.mod_mam_meta.pm.archive_groupchats = true`

When enabled, MAM will store groupchat messages in recipients' individual archives. **USE WITH CAUTION!** May increase archive size significantly. Disabling this option for existing installation will neither remove such messages from MAM storage, nor will filter out them from search results.

#### `modules.mod_mam_meta.pm.same_mam_id_for_peers`
* **Syntax:** boolean
* **Default:** `false`
* **Example:** `modules.mod_mam_meta.pm.same_mam_id_for_peers = true`

When enabled, MAM will set the same MAM ID for both sender and recipient. This can be useful in combination with [retraction on the stanza-id](#retraction-on-the-stanza-id). Note that this might not work with clients across federation, as the recipient might not implement the same retraction, nor the same IDs.

### Enable MUC message archive

Archive for MUC messages can be enabled in one of two ways:

* Specify `[mod_mam_meta.muc]` section

```toml
[modules.mod_mam_meta]
[modules.mod_mam_meta.muc] # defining this section enables MUC support
```

* Define any MUC related option

```toml
[modules.mod_mam_meta]
  muc.backend = "rdbms" # enables MUC support and overrides its backend
```

### Disable MUC message archive

To disable archive for MUC messages please remove MUC section or any MUC related option from the config file.

### MUC-specific options

#### `modules.mod_mam_meta.muc.host`
* **Syntax:** string
* **Default:** `"conference.@HOST@"`
* **Example:** `modules.mod_mam_meta.muc.host = "conference.@HOST@"`

The MUC host that will be archived if MUC archiving is enabled.

!!! Warning
    If you are using MUC Light, make sure this option is set to the MUC Light domain

#### Example

The example below presents how to override common option for `muc` module specifically.
Please note that you can override all common options in similar way.

```toml
[modules.mod_mam_meta]
  backend = "rdbms"
  async_writer = true # this option enables async writer for RDBMS backend
  muc.async_writer = false # disable async writer for MUC archive only
```

### RDBMS backend options

These options will only have effect when the `rdbms` backend is used:

#### `modules.mod_mam_meta.cache_users`
* **Syntax:** boolean
* **Default:** `true`
* **Example:** `modules.mod_mam_meta.cache_users = false`

Enables Archive ID to integer mappings cache.

If caching is enabled, by default it will spawn its own [segmented cache](https://github.com/esl/segmented_cache) cache, with defaults as in [`mod_cache_users`](./mod_cache_users.md). To change these defaults, the same config can be accessed within the `cache` key. To see details about the meaning of each flag, see [`mod_cache_users`](./mod_cache_users.md). To reuse the cache already created by `mod_cache_users`, see the option below.

```toml
modules.mod_mam_meta.cache.strategy
modules.mod_mam_meta.cache.time_to_live
modules.mod_mam_meta.cache.number_of_segments
```

#### `modules.mod_mam_meta.cache.module`
* **Syntax:** string, one of `"mod_cache_users"` or `"internal"`
* **Default:** `internal`
* **Example:** `modules.mod_mam_meta.cache.module = "mod_cache_users`

Configures which cache to use, either start an internal instance, or reuse the cache created by `mod_cache_users`, if such module was enabled. Note that if reuse is desired – that is, `cache.module = "mod_cache_users"`, other cache configuration parameters are not allowed.

#### `modules.mod_mam_meta.rdbms_message_format`
* **Syntax:** string, one of `"internal"` and `"simple"`
* **Default:** `"internal"`
* **Example:** `modules.mod_mam_meta.rdbms_message_format = "simple"`

!!! Warning
    Archive MUST be empty to change this option

When set to `simple`, stores messages in XML and full JIDs.
When set to `internal`, stores messages and JIDs in internal format.

#### `modules.mod_mam_meta.async_writer`
* **Syntax:** boolean
* **Default:** `true`
* **Example:** `modules.mod_mam_meta.async_writer = false`

Enables an asynchronous writer that is faster than the synchronous one but harder to debug.
The async writers store batches of messages with a certain delay (see **flush_interval**), so the results of the lookup operations executed right after message routing may be incomplete until the configured time passes.

#### `modules.mod_mam_meta.flush_interval`
* **Syntax:** non-negative integer
* **Default:** `2000`
* **Example:** `modules.mod_mam_meta.flush_interval = 2000`

How often (in milliseconds) the buffered messages are flushed to a DB.

#### `modules.mod_mam_meta.max_batch_size`
* **Syntax:** non-negative integer
* **Default:** `30`
* **Example:** `modules.mod_mam_meta.max_batch_size = 30`

Max size of the batch insert query for an async writer.
If the buffer is full, messages are flushed to a database immediately and the flush timer is reset.

#### `modules.mod_mam_meta.pool_size`
* **Syntax:** non-negative integer
* **Default:** `32`
* **Example:** `modules.mod_mam_meta.pool_size = 30`

Number of workers in the pool.

### Common backend options

#### `modules.mod_mam_meta.user_prefs_store`
* **Syntax:** one of `"rdbms"`, `"cassandra"`, `"mnesia"`
* **Default:** not set
* **Example:** `modules.mod_mam_meta.user_prefs_store = "rdbms"`

Leaving this option unset will prevent users from setting their archiving preferences.
It will also increase performance.
The possible values are:

* `"rdbms"` (RDBMS backend only) - User archiving preferences saved in RDBMS. Slow and not recommended, but might be used for simplicity (keeping everything in RDBMS).
* `"cassandra"` (Cassandra backend only) - User archiving preferences are saved in Cassandra.
* `"mnesia"` (recommended) - User archiving preferences saved in Mnesia and accessed without transactions. Recommended in most deployments, could be overloaded with lots of users updating their preferences at once. There's a small risk of an inconsistent (in a rather harmless way) state of the preferences table.

#### `modules.mod_mam_meta.full_text_search`
* **Syntax:** boolean
* **Default:** `true`
* **Example:** `modules.mod_mam_meta.full_text_search = false`

Enables full text search in message archive (see *Full Text Search* paragraph).
Please note that the full text search is currently only implemented for `"rdbms"` and `"riak"` backends.
Also, full text search works only for messages archived while this option is enabled.

#### <a id="is_archivable_message"></a>`is_archivable_message/3` callback

`is_archivable_message` option has to name a module exporting `is_archivable_message/3` function conforming to the spec:

```erlang
-spec is_archivable_message(Mod :: module(), Dir :: incoming | outgoing,
                          Packet :: exml:element()) -> boolean().
```

Servers SHOULD NOT archive messages that do not have a `<body/>` child tag. Servers SHOULD NOT archive delayed messages.

By default, all messages that hold meaningful content, rather than state changes such as Chat State Notifications, are archived.

#### Archiving chat markers

Archiving chat markers can be enabled by setting `archive_chat_markers` option to `true`. However it only works if
`is_archivable_message` callback module is set to `mod_mam_utils` or isn't set at all.

When performing full text search chat markers are treated as if they had empty message body.

### Riak backend

The Riak KV backend for MAM stores messages in weekly buckets so it's easier to remove old buckets.
Archive querying is done using Riak KV 2.0 [search mechanism](http://docs.basho.com/riak/2.1.1/dev/using/search/) called Yokozuna.
Your instance of Riak KV must be configured with Yokozuna enabled.

This backend works with Riak KV 2.0 and above, but we recommend version 2.1.1.

#### Riak-specific options

#### `modules.mod_mam_meta.riak.bucket_type`
* **Syntax:** non-empty string
* **Default:** `"mam_yz"`
* **Example:** `modules.mod_mam_meta.riak.bucket_type = "mam_yz"`

Riak bucket type.

#### `modules.mod_mam_meta.riak.search_index`
* **Syntax:** non-empty string
* **Default:** `"mam"`
* **Example:** `modules.mod_mam_meta.riak.search_index = "mam"`

Riak index name.

### Cassandra backend

Please consult [Outgoing connections](../configuration/outgoing-connections.md#cassandra-options) page to learn how to properly configure Cassandra connection pool.
By default, `mod_mam` Cassandra backend requires `global` pool with `default` tag.


### ElasticSearch backend

First, make sure that your ElasticSearch cluster has expected indexes and mappings in place.
Please consult [Outgoing connections](../configuration/outgoing-connections.md#elasticsearch-options) page to learn how to properly configure ElasticSearch connection pool.

### Low-level options

These options allow for fine-grained control over MAM behaviour.

#### `modules.mod_mam_meta.default_result_limit`
* **Syntax:** non-negative integer
* **Default:** `50`
* **Example:** `modules.mod_mam_meta.default_result_limit = 100`

This sets the default page size of returned results.

#### `modules.mod_mam_meta.max_result_limit`
* **Syntax:** non-negative integer
* **Default:** `50`
* **Example:** `modules.mod_mam_meta.max_result_limit = 100`

This sets the maximum page size of returned results.

#### `modules.mod_mam_meta.db_jid_format`

* **Syntax:** string, one of `"mam_jid_rfc"`, `"mam_jid_mini"` or a module implementing `mam_jid` behaviour
* **Default:** `"mam_jid_rfc"` for `mod_mam_muc_rdbms_arch`, `"mam_jid_mini"` for `mod_mam_rdbms_arch`
* **Example:** `modules.mod_mam_meta.db_jid_format = "mam_jid_mini"`

Sets the internal MAM jid encoder/decoder module for RDBMS.
It is set to `"mam_jid_rfc"` when [`rdbms_message_format`](#modulesmod_mam_metardbms_message_format) is set to `"simple"`.

#### `modules.mod_mam_meta.db_message_format`

* **Syntax:** string, one of `"mam_message_xml"`, `"mam_message_eterm"`, `"mam_message_compressed_eterm"` or a module implementing `mam_message` behaviour
* **Default:** different values for different backends, described below.
* **Example:** `modules.mod_mam_meta.db_message_format = "mam_message_compressed_eterm"`

Sets the internal MAM message encoder/decoder module.
Default values for:

* RDBMS: `"mam_message_compressed_eterm"` by default, and `"mam_message_xml"` when [`rdbms_message_format`](#modulesmod_mam_metardbms_message_format) is set to `"simple"`
* Riak: `"mam_message_xml"`
* Cassandra: `"mam_message_compressed_eterm"`  by default, and `"mam_message_xml"` when [`simple`](#modulesmod_mam_metasimple) is set to `true`

#### `modules.mod_mam_meta.simple`

* **Syntax:** boolean
* **Default:** `false`
* **Example:** `modules.mod_mam_meta.simple = true`

Sets `db_message_format` to `"mam_message_xml"` for Cassandra.

#### `modules.mod_mam_meta.extra_fin_element`

* **Syntax:** string, a module implementing the `extra_fin_element/3` callback
* **Default:** none
* **Example:** `modules.mod_mam_meta.extra_fin_element = "example_mod"`

This module can be used to add subelements to the `<fin>` element of the MAM lookup query response.
It can be useful to be able to add information to a mam query, that doesn't belong to any specific message but to all of them.

#### `modules.mod_mam_meta.extra_lookup_params`

* **Syntax:** string, a module implementing the `extra_lookup_params/2` callback
* **Default:** none
* **Example:** `modules.mod_mam_meta.extra_lookup_params = "example_mod"`

This module can be used to add extra lookup parameters to MAM lookup queries.

## Example configuration

```toml
[modules.mod_mam_meta]
  backend = "rdbms"
  no_stanzaid_element = true

  pm.user_prefs_store = "rdbms"

  muc.host = "muc.example.com"
  muc.rdbms_message_format = "simple"
  muc.async_writer = false
  muc.user_prefs_store = "mnesia"

```

## Metrics

If you'd like to learn more about metrics in MongooseIM, please visit [MongooseIM metrics](../operation-and-maintenance/MongooseIM-metrics.md) page.

| Name | Type | Description (when it gets incremented) |
| ---- | ---- | -------------------------------------- |
| `[HostType, modMamArchiveRemoved]` | spiral | User's entire archive is removed. |
| `[HostType, modMamArchived]` | spiral | A message is stored in user's archive. |
| `[HostType, modMamDropped]` | spiral | A message couldn't be stored in the DB (and got dropped). |
| `[HostType, modMamDroppedIQ]` | spiral | MAM IQ has been dropped due to: high query frequency/invalid syntax or type. |
| `[HostType, modMamFlushed]` | spiral | Message was stored in a DB asynchronously. |
| `[HostType, modMamForwarded]` | spiral | A message is sent to a client as a part of a MAM query result. |
| `[HostType, modMamLookups]` | spiral | A MAM lookup is performed. |
| `[HostType, modMamPrefsGets]` | spiral | Archiving preferences have been requested by a client. |
| `[HostType, modMamPrefsSets]` | spiral | Archiving preferences have been updated by a client. |
| `[HostType, modMucMamArchiveRemoved]` | spiral | Room's entire archive is removed. |
| `[HostType, modMucMamArchived]` | spiral | A message is stored in room's archive. |
| `[HostType, modMucMamForwarded]` | spiral | A message is sent to a client as a part of a MAM query result from MUC room. |
| `[HostType, modMucMamLookups]` | spiral | A MAM lookup in MUC room is performed. |
| `[HostType, modMucMamPrefsGets]` | spiral | MUC archiving preferences have been requested by a client. |
| `[HostType, modMucMamPrefsSets]` | spiral | MUC archiving preferences have been updated by a client. |
| `[HostType, mod_mam_rdbms_async_pool_writer, per_message_flush_time]` | histogram | Average time per message insert measured in an async MAM worker. |
| `[HostType, mod_mam_rdbms_async_pool_writer, flush_time]` | histogram | Average time per flush of all buffered messages measured in an async MAM worker. |
| `[HostType, mod_mam_muc_rdbms_async_pool_writer, per_message_flush_time]` | histogram | Average time per message insert measured in an async MUC MAM worker. |
| `[HostType, mod_mam_muc_rdbms_async_pool_writer, flush_time]` | histogram | Average time per flush of all buffered messages measured in an async MUC MAM worker. |

| Backend action | Description (when it gets incremented) |
| -------------- | ---------------------------------------|
| `lookup` | A lookup in an archive. |
| `archive` | One message is saved in an archive. |
