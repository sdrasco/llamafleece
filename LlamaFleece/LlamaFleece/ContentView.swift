import SwiftUI
import AppKit

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    var text: String
    let isUser: Bool
    var isThought: Bool = false
}

// MARK: - Custom NSTextView Subclass for Enter Key Behavior

class EnterKeyTextView: NSTextView {
    /// Closure to be called when Enter (without Shift) is pressed.
    var onSubmit: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        // keyCode 36 is the Return key.
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            // Do not call super to prevent inserting a newline.
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - PaddedTextEditor with Dynamic Height

struct PaddedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onHeightChange: ((CGFloat) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = EnterKeyTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        // Add internal padding.
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = true
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        // Make sure the text container tracks the width of the text view.
        textView.textContainer?.widthTracksTextView = true
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.autohidesScrollers = true
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
                // Recalculate the required height.
                if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                    let usedRect = layoutManager.usedRect(for: textContainer)
                    let newHeight = usedRect.height + textView.textContainerInset.height * 2
                    onHeightChange?(newHeight)
                }
            }
        }
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaddedTextEditor
        
        init(_ parent: PaddedTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
                // Calculate the height needed.
                if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                    let usedRect = layoutManager.usedRect(for: textContainer)
                    let newHeight = usedRect.height + textView.textContainerInset.height * 2
                    parent.onHeightChange?(newHeight)
                }
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var selectedModel: String = ""
    @State private var models: [String] = []
    @State private var messageInput: String = ""
    @State private var chatHistory: [ChatMessage] = []
    
    // State variable for the dynamic height of the text entry.
    @State private var inputHeight: CGFloat = 40  // default height (about two lines)
    
    // New state variables for alerts.
    @State private var showOllamaAlert: Bool = false
    @State private var showNoModelAlert: Bool = false
    
    let ollamaManager = OllamaManager()
    
    var body: some View {
        VStack {
            // Chat History Display with auto-scrolling.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(chatHistory) { message in
                            HStack {
                                if message.isUser {
                                    Spacer()
                                    Text(message.text)
                                        .padding()
                                        .background(Color.blue.opacity(0.3))
                                        .cornerRadius(8)
                                } else {
                                    if message.isThought {
                                        Text(message.text)
                                            .italic()
                                            .padding()
                                            .background(Color.yellow.opacity(0.3))
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.yellow, lineWidth: 1)
                                            )
                                        Spacer()
                                    } else {
                                        Text(message.text)
                                            .padding()
                                            .background(Color.gray.opacity(0.3))
                                            .cornerRadius(8)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .id(message.id)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: chatHistory.count) { newCount, oldCount in
                    if let lastMessage = chatHistory.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Message Input Area using our custom PaddedTextEditor.
            VStack(spacing: 8) {
                PaddedTextEditor(text: $messageInput, onSubmit: {
                    sendMessage()
                }, onHeightChange: { newHeight in
                    // Allow the input box to grow beyond the default, but not smaller than default.
                    inputHeight = max(newHeight, 40)
                })
                .frame(height: inputHeight)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                .padding(.horizontal)
                
                // Bottom bar with model selection and Send button.
                HStack {
                    Menu {
                        if models.isEmpty {
                            Button("No models available", action: {})
                                .disabled(true)
                        } else {
                            ForEach(models, id: \.self) { model in
                                Button(action: {
                                    selectedModel = model // store the full model string
                                }) {
                                    Text(shortenModel(model))
                                }
                            }
                        }
                    } label: {
                        if !selectedModel.isEmpty {
                            Text(shortenModel(selectedModel))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        } else {
                            Text("Select Model")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Send") {
                        sendMessage()
                    }
                    .padding(.horizontal)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .onAppear {
            if !ollamaManager.isOllamaInstalled() {
                showOllamaAlert = true
            } else {
                loadModels()
            }
        }
        // Alert if ollama is not installed.
        .alert("Ollama Not Installed", isPresented: $showOllamaAlert) {
            Button("Download Ollama") {
                if let url = URL(string: "https://ollama.com/download") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Quit App", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text("OllamaFleece requires that you first install ollama. Please download and install it from https://ollama.com/download, then restart the OllamaFleece.")
        }
        // Alert if no model is installed.
        .alert("No Model Installed", isPresented: $showNoModelAlert) {
            Button("Install deepseek-r1:1.5b (1.1GB)") {
                installDefaultModel()
            }
            Button("Browse Library") {
                if let url = URL(string: "https://ollama.com/library") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Looks like you have Ollama, but haven't installed any models yet. We'll install the smallest DeepSeek model for you if you want.  That's called deepseek-r1:1.5b, and will cost 1.1GB disk space. Alternatively, you can browse the library at https://ollama.com/library and install one yourself if you're comfortable with that.")
        }
    }
    
    // MARK: - Helper Functions
    
    func loadModels() {
        let list = ollamaManager.listModels()
        // Assuming the first line is a header; if count <= 1 then no model is installed.
        if list.count <= 1 {
            showNoModelAlert = true
        } else {
            models = Array(list.dropFirst()).map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = models.first {
                selectedModel = first
            }
        }
    }
    
    func installDefaultModel() {
        let defaultModel = "deepseek-r1:1.5b"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        process.arguments = ["run", defaultModel]
        process.environment = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ]
        do {
            try process.run()
            process.waitUntilExit()
            // After installation, reload models.
            loadModels()
        } catch {
            // Handle error if needed.
        }
    }
    
    func shortenModel(_ model: String) -> String {
        let tokens = model.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if tokens.count >= 4 {
            let name = tokens[0]
            let size = tokens[2] + " " + tokens[3]
            return "\(name) (\(size))"
        }
        return model
    }
    
    func sendMessage() {
        guard !messageInput.isEmpty, !selectedModel.isEmpty else { return }
        
        // Append user's message.
        let userMessage = ChatMessage(text: messageInput, isUser: true)
        chatHistory.append(userMessage)
        
        // Insert an empty placeholder for the bot's response.
        chatHistory.append(ChatMessage(text: "", isUser: false, isThought: false))
        let placeholderIndex = chatHistory.count - 1
        
        let currentMessage = messageInput
        // Reset the input text and height.
        messageInput = ""
        inputHeight = 40
        
        var streamedResponse = ""
        var hasInsertedThinkHeader = false
        
        let modelId = selectedModel.split(separator: " ").first.map(String.init) ?? selectedModel
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        process.arguments = ["run", modelId]
        process.environment = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ]
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let chunk = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    streamedResponse += chunk
                    
                    let openCount = streamedResponse.components(separatedBy: "<think>").count - 1
                    let closeCount = streamedResponse.components(separatedBy: "</think>").count - 1
                    let inThought = openCount > closeCount
                    
                    var displayedText = streamedResponse
                        .replacingOccurrences(of: "<think>", with: "")
                        .replacingOccurrences(of: "</think>", with: "")
                    
                    if inThought && !hasInsertedThinkHeader {
                        displayedText = "my internal thoughts...\n" + displayedText
                        hasInsertedThinkHeader = true
                    }
                    
                    chatHistory[placeholderIndex].text = displayedText
                    chatHistory[placeholderIndex].isThought = inThought
                }
            }
        }
        
        do {
            try process.run()
            
            if let inputData = (currentMessage + "\n").data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(inputData)
                inputPipe.fileHandleForWriting.closeFile()
            }
            
            process.waitUntilExit()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            
            DispatchQueue.main.async {
                let parsedMessages = parseThinkBlocks(streamedResponse)
                if !parsedMessages.isEmpty {
                    chatHistory.remove(at: placeholderIndex)
                    chatHistory.append(contentsOf: parsedMessages)
                } else {
                    chatHistory[placeholderIndex].text = streamedResponse
                }
            }
        } catch {
            DispatchQueue.main.async {
                chatHistory[placeholderIndex].text = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    func parseThinkBlocks(_ text: String) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var remaining = text
        
        while let startRange = remaining.range(of: "<think>"),
              let endRange = remaining.range(of: "</think>") {
            let before = String(remaining[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                messages.append(ChatMessage(text: before, isUser: false))
            }
            let thought = String(remaining[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !thought.isEmpty {
                messages.append(ChatMessage(text: thought, isUser: false, isThought: true))
            }
            remaining = String(remaining[endRange.upperBound...])
        }
        
        let final = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty {
            messages.append(ChatMessage(text: final, isUser: false))
        }
        
        return messages
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
