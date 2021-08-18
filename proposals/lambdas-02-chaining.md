However, when we have many `...->` blocks nested inside one another the
increasing indentation and accumulated mental context could be troubling.

To help alleviate this, we will support an extra bit of syntax sugar in which
an "asynchronous tail call" (where a `...->` call is made at the end of an outer `...->` block) may have its syntax abbreviated, such that instead of seeing `...-> (` to begin a new block, you will see `...-> |` to begin a new pipe-delimited section in the existing block.

There is also a potential performance benefit to using the tail call pattern for an asynchronous sequence of events, because the heap-allocation needed for capturing lambda objects can be amortized to allocate once for the entire chain of events, with each step in the sequence of events corresponding to a different method of the same underlying runtime object.

Consider the following example of tail calls, which also demonstrates how conditional `break`s can be used even when tail calls to `...->` are in play.

```savi
transaction = Transaction.new(bob_account, alice_account, 500)

clearance_service.check_if_allowed(transaction) ...-> (
| is_allowed |
  break unless is_allowed
  transaction.debit_account.access ...->

| debit_account |
  if !debit_account.already_processed(transaction) (
    if (debit_account.balance >= transaction.amount) (
      debit_account.balance -= transaction.amount
    |
      notifications.failed_transaction(transaction, "insufficient funds")
      break
    )
    debit_account.mark_as_processed(transaction)
  )
  transaction.credit_account.access ...->

| credit_account |
  if !credit_account.already_processed(transaction) (
    credit_account.balance += transaction.amount
    credit_account.mark_as_processed(transaction)
    notifications.completed_transaction(transaction)
  )
)
```

Note that this is similar in ergonomics (though not in implementation details) to the JavaScript syntax for `await` inside of an `async` function. The initial/outermost `...-> (` block corresponds to the `async` function, and the inner `...-> |` steps correspond to the `await` keyword, as demonstrated with the above example rewritten in semantically equivalent JavaScript:

```js
const transaction = new Transaction(bob_account, alice_account, 500)

clearance_service.check_if_allowed(transaction, async (is_allowed) => {
  if (!is_allowed) return

  const debit_account = await transaction.debit_account.access()
  if (!debit_account.already_processed(transaction)) {
    if (debit_account.balance >= transaction.amount) {
      debit_account.balance -= transaction.amount
    } else {
      notifications.failed_transaction(transaction, "insufficient funds")
      return
    )
    debit_account.mark_as_processed(transaction)
  }

  const credit_account = await transaction.credit_account.access()
  if (!credit_account.already_processed(transaction)) {
    credit_account.balance += transaction.amount
    credit_account.mark_as_processed(transaction)
    notifications.completed_transaction(transaction)
  }
})
```

It's worth noting here as an aside that `await` semantics have been avoided in Pony because we never want an actor to block in the middle of a behavior, waiting for some certain input and unable to respond to other messages. Such a situation is strongly discouraged by the language as much as possible.

However, we successfully avoid that problem in the above design because it isn't the actor which is waiting for fulfillment, but rather the async runtime object itself (created through the `...->` syntax) that gets passed in messages from one actor to the next.