import Intents

/// CarPlay's assistant cell enters Siri here, then hands audio work to the app in background.
final class IntentHandler: INExtension, INPlayMediaIntentHandling {
  override func handler(for intent: INIntent) -> Any { self }
  func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void)
  {
    completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
  }
}
