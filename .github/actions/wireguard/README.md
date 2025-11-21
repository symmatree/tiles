# wireguard action

This is a fancy JS action because it is useful to actively close the VPN
connection, and simple composite actions cannot have `post` actions to do
the cleanup.

A possible alternative would be to just have two composite actions, since you CAN
run a shutdown step even on a prior failure, as long as you include
one or both of `success()` and `failed()` in your `if` condition. That would
be nice in terms of avoiding the introduction of a whole npm toolchain and
thing-to-know-about, simply for a "finally" block.
