## CanDB database structure

### "u/" - Principal -> User
- Attribute `"u"`: `"u"` - `User` record.
- Attribute `"v"` - `VotingInfo`.
### "e/" - Ethereum address -> Principal
- Attribute "p" - Principal
### "i/" - ID -> Item
- Attribute `"i"` - `Item` record.
- Attribute `"st"` (time), `"sv"` (votes) - `Streams` record.
- Attribute `"rst"` (time), `"rsv"` (votes) - `Streams` record, reverse order.
- Attribute `"t"` - post's text.
### "a/" - user -> <buyer affiliate>/<seller affiliate>
### "v/<principal>/<parent>/<child>"
- Attribute `"v"` -  `#int +-1` - votes
### "w/<parent>/<child>"
- Attribute `"v"` - `#tuple [#int <VOTES UP>, #int <VOTES DOWN>]`

## NacDB database structure
* time/time: folder -> sub-items
* time/time: folder -> sub-folders
* time/time: item -> comments
* votes/votes: folder -> sub-items
* votes/votes: folder -> sub-folders
* votes/votes: item -> comments

Allowed number of votes:
- 10 per day
- additional 5 votes (not per day) for each message