# iOS App Integration Guide for Web Component System

## Overview
This guide explains how to integrate the external phrase contribution system into your iOS app. The web infrastructure is now complete and ready for iOS integration.

## 1. Add Contribution Link Generation to NetworkManager

Add this method to `NetworkManager.swift`:

```swift
func requestContributionLink(expirationHours: Int = 48, maxUses: Int = 3, customMessage: String? = nil) async -> ContributionLinkResult? {
    guard let currentPlayer = currentPlayer else {
        print("❌ CONTRIBUTION: No current player")
        return nil
    }
    
    guard let url = URL(string: "\(baseURL)/api/contribution/request") else {
        print("❌ CONTRIBUTION: Invalid URL")
        return nil
    }
    
    do {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var requestBody: [String: Any] = [
            "playerId": currentPlayer.id,
            "expirationHours": expirationHours,
            "maxUses": maxUses
        ]
        
        if let customMessage = customMessage, !customMessage.isEmpty {
            requestBody["customMessage"] = customMessage
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, 
              httpResponse.statusCode == 201 else {
            print("❌ CONTRIBUTION: Failed to create link. Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return nil
        }
        
        let result = try JSONDecoder().decode(ContributionLinkResponse.self, from: data)
        print("✅ CONTRIBUTION: Link created successfully")
        return result.link
        
    } catch {
        print("❌ CONTRIBUTION: Error creating link: \(error.localizedDescription)")
        return nil
    }
}
```

## 2. Add Data Models

Add these data models to your project (e.g., in `Models/ContributionModels.swift`):

```swift
import Foundation

struct ContributionLinkResult: Codable {
    let id: String
    let token: String
    let url: String
    let shareableUrl: String
    let expiresAt: String
    let maxUses: Int
}

struct ContributionLinkResponse: Codable {
    let success: Bool
    let link: ContributionLinkResult
}
```

## 3. Add UI for Link Generation

Create a new view `ContributionLinkView.swift`:

```swift
import SwiftUI

struct ContributionLinkView: View {
    @Binding var isPresented: Bool
    @StateObject private var networkManager = NetworkManager.shared
    
    @State private var expirationHours = 48
    @State private var maxUses = 3
    @State private var customMessage = ""
    @State private var isLoading = false
    @State private var generatedLink: ContributionLinkResult?
    @State private var showingShareSheet = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let link = generatedLink {
                    // Show generated link
                    VStack(spacing: 16) {
                        Text("🎯 Contribution Link Created!")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Share this link with friends to contribute phrases to your game:")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Link Details:")
                                .font(.headline)
                            
                            Text("• Expires: \(formatDate(link.expiresAt))")
                            Text("• Uses: \(link.maxUses) maximum")
                            if !customMessage.isEmpty {
                                Text("• Message: \(customMessage)")
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        Button(action: {
                            showingShareSheet = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Link")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                } else {
                    // Show link creation form
                    VStack(spacing: 16) {
                        Text("Request External Phrase")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Generate a link that friends can use to contribute phrases to your game")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Expiration Time")
                                .font(.headline)
                            
                            Picker("Hours", selection: $expirationHours) {
                                Text("24 hours").tag(24)
                                Text("48 hours").tag(48)
                                Text("72 hours").tag(72)
                                Text("1 week").tag(168)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Maximum Uses")
                                .font(.headline)
                            
                            Picker("Uses", selection: $maxUses) {
                                Text("1 use").tag(1)
                                Text("3 uses").tag(3)
                                Text("5 uses").tag(5)
                                Text("10 uses").tag(10)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Custom Message (Optional)")
                                .font(.headline)
                            
                            TextField("Add a personal message...", text: $customMessage)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        Button(action: generateLink) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "link")
                                }
                                Text(isLoading ? "Generating..." : "Generate Link")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isLoading ? Color.gray : Color.blue)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading)
                    }
                }
                
                Spacer()
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
            .navigationTitle("External Contribution")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                if generatedLink != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = generatedLink {
                ShareSheet(activityItems: [link.shareableUrl])
            }
        }
    }
    
    private func generateLink() {
        isLoading = true
        errorMessage = ""
        
        Task {
            let link = await networkManager.requestContributionLink(
                expirationHours: expirationHours,
                maxUses: maxUses,
                customMessage: customMessage.isEmpty ? nil : customMessage
            )
            
            await MainActor.run {
                isLoading = false
                if let link = link {
                    generatedLink = link
                } else {
                    errorMessage = "Failed to generate contribution link. Please try again."
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

## 4. Integrate into Your Main Navigation

Add the contribution link option to your main game interface. For example, in your `LobbyView.swift` or main menu:

```swift
Button(action: {
    showingContributionLink = true
}) {
    HStack {
        Image(systemName: "link.badge.plus")
        Text("Request External Phrase")
    }
    .font(.subheadline)
    .foregroundColor(.blue)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.blue.opacity(0.1))
    .cornerRadius(8)
}
.sheet(isPresented: $showingContributionLink) {
    ContributionLinkView(isPresented: $showingContributionLink)
}
```

## 5. Add State Variables

Add these state variables to the view where you're adding the button:

```swift
@State private var showingContributionLink = false
```

## 6. Test the Integration

1. **Start the server** with the new web components:
   ```bash
   cd server
   node server.js
   ```

2. **Test link generation** in the iOS app
3. **Share the generated link** via Messages, Email, etc.
4. **Open the link** in a web browser to test the contribution form
5. **Verify phrases appear** in your game queue

## Available Endpoints

Your iOS app can now interact with these endpoints:

- `POST /api/contribution/request` - Generate contribution link
- `GET /api/contribution/:token` - Validate link (used by web form)
- `POST /api/contribution/:token/submit` - Submit phrase (used by web form)
- `GET /monitoring` - View monitoring dashboard
- `GET /contribute/:token` - Contribution form (web interface)

## Security Considerations

- Links expire automatically (default 48 hours)
- Limited number of uses per link (default 3)
- Input validation matches your app's phrase requirements
- Rate limiting prevents abuse
- Contributor IP addresses are logged

## Monitoring

Visit `/monitoring` in your web browser to see:
- Real-time game activity
- Online player count
- Phrase creation statistics
- Contribution link usage

## Customization Options

You can customize the contribution experience by:
- Adjusting expiration times (24h to 1 week)
- Setting usage limits (1-10 uses per link)
- Adding custom messages for contributors
- Modifying the web form styling in `/web-dashboard/public/contribute/`

The web infrastructure handles all the complex parts - your iOS app just needs to generate links and display them to users!