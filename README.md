# biscuit-zig

Zig implementation of https://www.biscuitsec.org/

## Usage

### Authorizing a token

```zig
var biscuit = try Biscuit.fromBytes(allocator, token, root_public_key);
defer biscuit.deinit();

var authorizer = try biscuit.authorizer();
defer authorizer.deinit();

var errors = std.ArrayList(AuthorizerError).init(allocator);
defer errors.deinit();

try authorizer.authorize(&errors);
```

### Attenuating a token

```zig
var biscuit = try Biscuit.fromBytes(allocator, token, root_public_key);
defer biscuit.deinit();

var authorizer = try biscuit.authorizer();
defer authorizer.deinit();

var errors = std.ArrayList(AuthorizerError).init(allocator);
defer errors.deinit();

try authorizer.authorize(&errors);
```
