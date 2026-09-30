# Using Apple's StoreKit APIs with Godot

This guide explains the StoreKit workflow in this addon. For Apple platform
rules and App Store Connect setup, see [Apple's StoreKit documentation](https://developer.apple.com/documentation/storekit).

# Table of Contents

* [Start StoreKit](#start-storekit)
* [Handle transactions](#handle-transactions)
* [Check current entitlements at startup](#check-current-entitlements-at-startup)
* [Redeem offer codes](#redeem-offer-codes)
* [Handle external offer-code redemptions](#handle-external-offer-code-redemptions)
* [Test offer codes](#test-offer-codes)

# Start StoreKit

Create one `StoreKitManager` when your app starts. Keep it alive for the life
of the app. Connect signals before you call `start()`.

`start()` begins the StoreKit transaction listener. It also checks for
unfinished transactions. This lets your app recover purchases that happened
while it was not running.

```gdscript
var store_kit: StoreKitManager

func _ready() -> void:

	store_kit = StoreKitManager.new()
	store_kit.transaction_updated.connect(_on_transaction_updated)
	store_kit.unverified_transaction_updated.connect(_on_unverified_transaction_updated)
	store_kit.start()

func _on_unverified_transaction_updated(
	transaction: StoreTransaction,
	verification_error: int
) -> void:

	push_warning("StoreKit could not verify transaction %s" % transaction.transaction_id)
```

Do not create a manager only when a user opens a store screen. StoreKit can
send transactions at any time.

# Handle transactions

`transaction_updated` contains verified transactions from purchases, offer
codes, subscriptions, and purchases that happen outside your app. Deliver the
product first. Then call `finish()`.

Make delivery idempotent. A transaction can be sent again until you finish it.
If delivery changes saved or server state, store the transaction ID as part of
the same operation.

```gdscript
func _on_transaction_updated(transaction: StoreTransaction) -> void:

	match transaction.product_id:
		"com.example.game.coins.100":
			add_coins(100)
		"com.example.game.remove_ads":
			unlock_remove_ads()
		"com.example.game.full_version":
			unlock_full_version()
		_:
			push_warning("Unknown product: %s" % transaction.product_id)
			return

	transaction.finish()
```

`fetch_current_entitlements()` is useful for non-consumables and subscriptions.
It does not return consumables. Use unfinished transactions to recover a
consumable purchase that the app did not finish. `start()` does this
automatically. You can call `fetch_unfinished_transactions()` again to retry.

# Check current entitlements at startup

Connect `current_entitlements_fetch_completed` before you call
`fetch_current_entitlements()`. The method sends each verified entitlement
through `transaction_updated` and each unverified entitlement through
`unverified_transaction_updated`. It then sends
`current_entitlements_fetch_completed` with an array of verified current
entitlements. The array is empty when StoreKit finds no verified current
entitlements. The completion signal also fires for this empty result.

Use the array to select the first screen. It contains only entitlements from
this check, so other transaction updates cannot change the result. In this
example, `com.example.game.full_version` is a non-consumable purchase:

```gdscript
const FULL_VERSION_ID = "com.example.game.full_version"

var store_kit: StoreKitManager

func _ready() -> void:
	store_kit = StoreKitManager.new()
	store_kit.transaction_updated.connect(_on_transaction_updated)
	store_kit.unverified_transaction_updated.connect(_on_unverified_transaction_updated)
	store_kit.current_entitlements_fetch_completed.connect(_on_current_entitlements_fetch_completed)
	store_kit.start()
	store_kit.fetch_current_entitlements()

func _on_current_entitlements_fetch_completed(
	entitlements: Array[StoreTransaction]
) -> void:
	for entitlement in entitlements:
		if entitlement.product_id == FULL_VERSION_ID:
			get_tree().change_scene_to_file("res://full_menu.tscn")
			return
	get_tree().change_scene_to_file("res://demo_menu.tscn")
```

Use the transaction handlers in the earlier examples to deliver and finish
transactions. Do not grant access for an unverified transaction. StoreKit does
not include consumables in current entitlements.

# Redeem offer codes

Offer codes can apply to consumables, non-consumables, non-renewing
subscriptions, and auto-renewable subscriptions. Configure the offer for the
exact product in App Store Connect before you show the redemption sheet.

Use `SubscriptionOfferView` to show the Apple redemption sheet. Do not make a
custom code-entry screen. The `success` signal confirms that the code
redemption flow completed. The resulting product transaction arrives through
`StoreKitManager.transaction_updated`; grant the product there.

```gdscript
var offer_view: SubscriptionOfferView

func show_offer_code_redemption() -> void:

	offer_view = SubscriptionOfferView.new()
	offer_view.success.connect(func() -> void:
		print("Offer code redeemed. Waiting for its transaction.")
	)
	offer_view.error.connect(func(message: String) -> void:
		push_warning(message)
	)
	offer_view.present()
```

In-app redemption for consumables, non-consumables, and non-renewing
subscriptions requires iOS or iPadOS 16.3 or later. It requires macOS 15 or
later on Mac. No extra app entitlement is required.

# Handle external offer-code redemptions

Users can redeem codes in the App Store or from a redemption URL. If your app
is running, StoreKit sends the resulting transaction through
`transaction_updated`. If it is not running, `start()` reads the unfinished
transaction on the next launch and emits the same signal.

For a consumable, do not use `fetch_current_entitlements()` as recovery. Apple
does not include consumables in that list. Deliver the unfinished transaction
and finish it.

If you have a server, enable App Store Server Notifications V2. Apple sends a
`ONE_TIME_CHARGE` notification for a consumable offer-code redemption. Use the
server notification as a second record of the event, but still handle the
device transaction to grant the item without delay.

# Test offer codes

For Sandbox testing, create sandbox offer codes for the product in App Store
Connect. Sign in with a Sandbox Apple Account on the test device. Then use the
offer-code sheet in your app, or start an offer-code transaction from Sandbox
Account Settings.

You can also use a StoreKit configuration file in Xcode. Add an offer code to
the test product. Use Xcode's StoreKit Transaction Manager to simulate a code
redemption that happens outside the app.

Custom and one-time production codes require an approved In-App Purchase and
an app that is Ready for Distribution. A new code batch can take up to one hour
before customers can redeem it.
