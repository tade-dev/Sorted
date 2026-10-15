import receive_sharing_intent

/// Sorted's Share Extension. No compose card: the screenshot or text goes
/// straight to the app, which opens Reading (ShareSheet.dc.html shows only the
/// OS share sheet, with Sorted as the target).
class ShareViewController: RSIShareViewController {
    override func shouldAutoRedirect() -> Bool {
        return true
    }
}
