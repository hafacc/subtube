import SwiftUI

/// The field a phrase is typed into. Return, and leaving the field, hand
/// the text to `onSubmit`; Delete in the empty field calls
/// `onDeleteWhenEmpty`. The system's own field is used because SwiftUI's
/// doesn't report either key on a phone.
struct PhraseInput {
  @Binding var text: String
  let prompt: String
  let onSubmit: () -> Void
  let onDeleteWhenEmpty: () -> Void

  @MainActor
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  @MainActor
  final class Coordinator: NSObject {
    var input: PhraseInput

    init(_ input: PhraseInput) {
      self.input = input
    }
  }
}

#if os(macOS)
  extension PhraseInput: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextField {
      let field = NSTextField()
      field.placeholderString = prompt
      field.delegate = context.coordinator
      field.isAutomaticTextCompletionEnabled = false
      field.setContentHuggingPriority(.defaultLow, for: .horizontal)
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      field.setAccessibilityLabel(prompt)
      return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
      context.coordinator.input = self
      if field.stringValue != text {
        field.stringValue = text
      }
    }
  }

  extension PhraseInput.Coordinator: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
      if let field = notification.object as? NSTextField {
        input.text = field.stringValue
      }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      if let field = notification.object as? NSTextField, !field.stringValue.isEmpty {
        input.onSubmit()
      }
    }

    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        input.onSubmit()
        return true
      } else if commandSelector == #selector(NSResponder.deleteBackward(_:)),
        textView.string.isEmpty
      {
        input.onDeleteWhenEmpty()
        return true
      } else {
        return false
      }
    }
  }
#else
  extension PhraseInput: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextField {
      let field = DeleteReportingTextField()
      field.placeholder = prompt
      field.accessibilityLabel = prompt
      field.delegate = context.coordinator
      field.autocorrectionType = .no
      field.autocapitalizationType = .none
      field.spellCheckingType = .no
      field.returnKeyType = .done
      field.font = .preferredFont(forTextStyle: .body)
      field.adjustsFontForContentSizeCategory = true
      field.setContentHuggingPriority(.defaultLow, for: .horizontal)
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      field.addTarget(
        context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
      field.onDeleteWhenEmpty = { [coordinator = context.coordinator] in
        coordinator.input.onDeleteWhenEmpty()
      }
      return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
      context.coordinator.input = self
      if field.text != text {
        field.text = text
      }
    }
  }

  extension PhraseInput.Coordinator: UITextFieldDelegate {
    @objc func changed(_ field: UITextField) {
      input.text = field.text ?? ""
    }

    func textFieldShouldReturn(_ field: UITextField) -> Bool {
      input.onSubmit()
      return false
    }

    func textFieldDidEndEditing(_ field: UITextField) {
      if !(field.text ?? "").isEmpty {
        input.onSubmit()
      }
    }
  }

  private final class DeleteReportingTextField: UITextField {
    var onDeleteWhenEmpty: (() -> Void)?

    override func deleteBackward() {
      if text?.isEmpty ?? true {
        onDeleteWhenEmpty?()
      }
      super.deleteBackward()
    }
  }
#endif
