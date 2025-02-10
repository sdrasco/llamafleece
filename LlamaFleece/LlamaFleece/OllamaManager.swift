import Foundation

class OllamaManager {
    
    // MARK: - Installation Check
    
    /// Returns true if `ollama` is found in the system PATH.
    func isOllamaInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ollama"]
        process.environment = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !output.isEmpty
        } catch {
            print("Error checking for ollama: \(error)")
            return false
        }
    }
    
    // MARK: - Model Listing
    
    /// Lists available models by invoking `ollama list`.
    func listModels() -> [String] {
        let output = runCommand("/usr/local/bin/ollama", arguments: ["list"])
        return output.split(separator: "\n").map { String($0) }
    }
    
    // MARK: - Message Dispatch
    
    /// Sends a message to a specified model by invoking `ollama run <model>`
    /// and writing the message to standard input.
    func sendMessage(_ message: String, usingModel model: String) -> String {
        // Extract the model ID from the selected model line.
        // Assumes the model ID is the first token in the line.
        let modelId = model.split(separator: " ").first.map(String.init) ?? model
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        process.arguments = ["run", modelId]
        process.environment = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ]
        
        // Set up pipes for sending input and receiving output.
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        
        do {
            try process.run()
            
            // Write the message (plus a newline) to standard input.
            if let data = (message + "\n").data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
                inputPipe.fileHandleForWriting.closeFile() // Signal EOF.
            }
            
            process.waitUntilExit()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
        } catch {
            print("Error sending message: \(error)")
            return "Error: \(error)"
        }
    }
    
    // MARK: - Utility
    
    /// Runs a shell command with the given arguments and returns its standard output.
    private func runCommand(_ command: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
        } catch {
            print("Command error: \(error)")
            return "Error: \(error)"
        }
    }
}
