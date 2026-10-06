import SubtubeCore
import SwiftUI

/// The Settings window: General (theme) and Account (sync, sign out, delete
/// profile).
struct MacSettingsView: View {
  let app: AppModel

  var body: some View {
    TabView {
      Tab(Strings.general, systemImage: "gearshape") {
        Form {
          ThemePicker(app: app)
        }
        .formStyle(.grouped)
      }
      Tab(Strings.account, systemImage: "person.crop.circle") {
        MacAccountPane(app: app)
      }
    }
    .frame(width: 520)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear { app.feed?.reorderChannels() }
    .onDisappear { app.feed?.reorderChannels() }
  }
}

private struct MacAccountPane: View {
  let app: AppModel

  var body: some View {
    Form {
      if let feed = app.feed {
        Section {
          AccountSummary(feed: feed)
        }
        Section {
          SyncStatus(feed: feed)
        }
        Section {
          VStack(alignment: .leading, spacing: 6) {
            Button(Strings.signOut, role: .destructive) {
              Task { await app.signOut() }
            }
            Text(Strings.signOutFootnote)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        Section {
          VStack(alignment: .leading, spacing: 6) {
            DeleteProfileButton(app: app)
            DeleteProfileFootnote(app: app)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 6) {
          GoogleSignInButton(app: app)
          SignInAgreement()
          if let error = app.error {
            Text(error).font(.callout).foregroundStyle(.red)
          }
        }
      }
      Section {
        LegalLinks()
      }
    }
    .formStyle(.grouped)
  }
}
