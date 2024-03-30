# Design

## Memory Management

Authorizing a biscuit is a short-lived single pass operation. This makes arena allocation
a great candidate for large parts of biscuit memory management:

- It can greatly reduce the complexity of code that would otherwise have to carefully clone
  / move memory to avoid leaks and double frees.
- Potentially code can be faster because we don't do granular deallocation and we can avoid
  some copying.
- Again, because we're not necessarily copying, there is the potential for reduced memory usage
  in places.

The disadvantage would be that:

- We potentially over allocate, i.e. we are storing more in memory than we technically need to.

We create a toplevel arena and into it allocate all:

- facts
- predicates
- rules
- queries
- policies
- expressions
- ops
- terms

i.e. all the domain level objects are arena allocated. This means we don't have to do
complex reasoning about scope / lifetimes of these objects, they are all valid until
the toplevel arena is deallocated. If we are careful to always copy when modifying
one of these resources we can also share resources.
