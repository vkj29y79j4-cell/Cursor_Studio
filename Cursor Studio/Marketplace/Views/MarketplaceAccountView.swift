import SwiftUI

struct MarketplaceAccountView: View {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var model: MarketplaceAccountViewModel
    let localThemes: [CursorTheme]
    let selectedThemeID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    model.isSignedIn
                        ? L10n.creatorCenter
                        : L10n.marketplaceAccount
                )
                .font(.title2.bold())
                Spacer()
                Button(L10n.done) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            if model.isRestoringSession {
                ProgressView(L10n.restoringSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isSignedIn {
                CreatorCenterView(
                    appModel: appModel,
                    model: model,
                    localThemes: localThemes,
                    selectedThemeID: selectedThemeID
                )
            } else {
                MarketplaceAuthenticationView(model: model)
            }
        }
        .frame(width: 760, height: 680)
        .task {
            await model.restoreSessionIfNeeded()
        }
        .alert(
            L10n.marketplaceError,
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button(L10n.ok) {
                model.errorMessage = nil
            }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }
}

private struct MarketplaceAuthenticationView: View {
    enum Mode: String, CaseIterable {
        case signIn
        case createAccount

        var title: String {
            switch self {
            case .signIn: L10n.signIn
            case .createAccount: L10n.createAccount
            }
        }
    }

    @ObservedObject var model: MarketplaceAccountViewModel
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var handle = ""
    @State private var displayName = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(L10n.marketplaceWelcome)
                    .font(.title.bold())
                Text(L10n.accountNeededForPublishing)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker(L10n.marketplaceAccount, selection: $mode) {
                ForEach(Mode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            VStack(spacing: 12) {
                TextField(L10n.email, text: $email)
                    .textContentType(.emailAddress)

                if mode == .createAccount {
                    TextField(L10n.creatorHandle, text: $handle)
                        .textContentType(.username)
                    TextField(L10n.displayName, text: $displayName)
                        .textContentType(.name)
                }

                SecureField(L10n.password, text: $password)
                    .textContentType(
                        mode == .signIn ? .password : .newPassword
                    )
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 360)

            if let notice = model.noticeMessage {
                Label(notice, systemImage: "envelope.badge")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button(mode.title) {
                Task {
                    let succeeded: Bool
                    switch mode {
                    case .signIn:
                        succeeded = await model.signIn(
                            email: email,
                            password: password
                        )
                    case .createAccount:
                        succeeded = await model.signUp(
                            email: email,
                            password: password,
                            handle: handle,
                            displayName: displayName
                        )
                    }
                    if succeeded {
                        password = ""
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                model.isWorking
                    || email.isEmpty
                    || password.isEmpty
                    || (
                        mode == .createAccount
                            && (handle.isEmpty || displayName.isEmpty)
                    )
            )

            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Text(L10n.credentialsHandledBySupabase)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(32)
        .onChange(of: mode) {
            model.dismissMessages()
        }
    }
}

private struct CreatorCenterView: View {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var model: MarketplaceAccountViewModel
    let localThemes: [CursorTheme]
    let selectedThemeID: UUID?

    var body: some View {
        TabView {
            CreatorProfileView(model: model)
                .tabItem {
                    Label(L10n.profile, systemImage: "person.crop.circle")
                }

            PublishThemeView(
                model: model,
                localThemes: localThemes,
                selectedThemeID: selectedThemeID
            )
            .tabItem {
                Label(L10n.publish, systemImage: "square.and.arrow.up")
            }

            CreatorSubmissionsView(model: model)
                .tabItem {
                    Label(L10n.mySubmissions, systemImage: "tray.full")
                }

            if model.isModerator {
                ModeratorCenterView(
                    appModel: appModel,
                    model: model
                )
                    .tabItem {
                        Label(
                            L10n.moderation,
                            systemImage: "checkmark.shield"
                        )
                    }
            }
        }
        .padding(12)
        .overlay(alignment: .top) {
            if let notice = model.noticeMessage {
                HStack {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button {
                        model.noticeMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.close)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 4)
            }
        }
    }
}

private struct CreatorProfileView: View {
    @ObservedObject var model: MarketplaceAccountViewModel
    @State private var handle = ""
    @State private var displayName = ""
    @State private var bio = ""

    var body: some View {
        Form {
            Section(L10n.marketplaceAccount) {
                LabeledContent(
                    L10n.email,
                    value: model.account?.email ?? "—"
                )
                if model.isModerator {
                    Label(
                        L10n.moderatorAccount,
                        systemImage: "checkmark.shield.fill"
                    )
                    .foregroundStyle(.blue)
                }
            }

            Section(L10n.publicProfile) {
                TextField(L10n.creatorHandle, text: $handle)
                TextField(L10n.displayName, text: $displayName)
                TextField(L10n.bio, text: $bio, axis: .vertical)
                    .lineLimit(3...6)

                Button(L10n.saveProfile) {
                    Task {
                        _ = await model.saveProfile(
                            handle: handle,
                            displayName: displayName,
                            bio: bio
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)
            }

            Section {
                Button(L10n.signOut, role: .destructive) {
                    Task { await model.signOut() }
                }
                .disabled(model.isWorking)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            copyProfile()
        }
        .onChange(of: model.profile) {
            copyProfile()
        }
    }

    private func copyProfile() {
        guard let profile = model.profile else { return }
        handle = profile.handle
        displayName = profile.displayName
        bio = profile.bio ?? ""
    }
}

private struct PublishThemeView: View {
    @ObservedObject var model: MarketplaceAccountViewModel
    let localThemes: [CursorTheme]
    @State private var localThemeID: UUID?
    @State private var titleEN = ""
    @State private var titleRU = ""
    @State private var descriptionEN = ""
    @State private var descriptionRU = ""
    @State private var semanticVersion = "1.0.0"
    @State private var categoryID: UUID?
    @State private var acceptsGuidelines = false

    init(
        model: MarketplaceAccountViewModel,
        localThemes: [CursorTheme],
        selectedThemeID: UUID?
    ) {
        self.model = model
        self.localThemes = localThemes
        _localThemeID = State(
            initialValue: selectedThemeID ?? localThemes.first?.id
        )
    }

    private var selectedTheme: CursorTheme? {
        localThemeID.flatMap { id in
            localThemes.first { $0.id == id }
        }
    }

    var body: some View {
        Form {
            Section(L10n.localTheme) {
                Picker(L10n.theme, selection: $localThemeID) {
                    ForEach(localThemes) { theme in
                        Text(theme.name).tag(Optional(theme.id))
                    }
                }

                if let selectedTheme {
                    LabeledContent(
                        L10n.includedCursors,
                        value: L10n.cursorCount(selectedTheme.entries.count)
                    )
                }
            }

            Section(L10n.marketplaceListing) {
                TextField(L10n.titleEnglish, text: $titleEN)
                TextField(L10n.titleRussianOptional, text: $titleRU)
                TextField(
                    L10n.descriptionEnglish,
                    text: $descriptionEN,
                    axis: .vertical
                )
                .lineLimit(3...5)
                TextField(
                    L10n.descriptionRussianOptional,
                    text: $descriptionRU,
                    axis: .vertical
                )
                .lineLimit(3...5)

                Picker(L10n.category, selection: $categoryID) {
                    Text(L10n.selectCategory)
                        .tag(UUID?.none)
                    ForEach(model.categories) { category in
                        Text(category.displayName)
                            .tag(Optional(category.id))
                    }
                }

                TextField(L10n.semanticVersion, text: $semanticVersion)
            }

            Section {
                Toggle(
                    L10n.acceptCreatorGuidelines,
                    isOn: $acceptsGuidelines
                )
                Text(L10n.publishUploadNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(L10n.submitForReview) {
                    guard let selectedTheme, let categoryID else { return }
                    Task {
                        let succeeded = await model.publish(
                            theme: selectedTheme,
                            request: MarketplacePublishRequest(
                                titleEN: titleEN,
                                titleRU: titleRU,
                                descriptionEN: descriptionEN,
                                descriptionRU: descriptionRU,
                                semanticVersion: semanticVersion,
                                categoryID: categoryID
                            )
                        )
                        if succeeded {
                            acceptsGuidelines = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.isWorking
                        || selectedTheme == nil
                        || categoryID == nil
                        || titleEN.isEmpty
                        || descriptionEN.isEmpty
                        || !acceptsGuidelines
                )

                if model.categories.isEmpty {
                    Label(
                        L10n.noMarketplaceCategories,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            synchronizeThemeDefaults()
            categoryID = categoryID ?? model.categories.first?.id
        }
        .onChange(of: localThemeID) {
            synchronizeThemeDefaults()
        }
        .onChange(of: model.categories) {
            categoryID = categoryID ?? model.categories.first?.id
        }
    }

    private func synchronizeThemeDefaults() {
        guard let selectedTheme else { return }
        if titleEN.isEmpty {
            titleEN = selectedTheme.name
        }
    }
}

private struct CreatorSubmissionsView: View {
    @ObservedObject var model: MarketplaceAccountViewModel

    var body: some View {
        Group {
            if model.submissions.isEmpty {
                ContentUnavailableView {
                    Label(L10n.noSubmissions, systemImage: "tray")
                } description: {
                    Text(L10n.noSubmissionsDetail)
                }
            } else {
                List(model.submissions) { submission in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(submission.title)
                                .font(.headline)
                            Text("v\(submission.semanticVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(submission.status.displayName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(
                                submissionColor(submission.status)
                            )
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .toolbar {
            Button {
                Task { await model.reloadCreatorData() }
            } label: {
                Label(L10n.refresh, systemImage: "arrow.clockwise")
            }
        }
    }

    private func submissionColor(
        _ status: MarketplaceReviewStatus
    ) -> Color {
        switch status {
        case .draft: .secondary
        case .pending: .orange
        case .approved: .green
        case .rejected: .red
        }
    }
}

private struct ModeratorCenterView: View {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var model: MarketplaceAccountViewModel
    @State private var selectedItem: MarketplaceModerationItem?
    @State private var moderatorHandle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(L10n.reviewQueue)
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        Task { await model.reloadCreatorData() }
                    } label: {
                        Label(L10n.refresh, systemImage: "arrow.clockwise")
                    }
                }

                if model.moderationQueue.isEmpty {
                    ContentUnavailableView {
                        Label(
                            L10n.moderationQueueEmpty,
                            systemImage: "checkmark.circle"
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    ForEach(model.moderationQueue) { item in
                        HStack(alignment: .top, spacing: 14) {
                            ModerationPreviewImage(
                                url: item.previewURL,
                                height: 88
                            )
                            .frame(width: 132)

                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(
                                        "@\(item.creatorHandle) · v\(item.semanticVersion)"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Text(item.description)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack {
                                    Text(
                                        L10n.cursorCount(
                                            item.includedRoles.count
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    Spacer()
                                    Button(L10n.review) {
                                        selectedItem = item
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                }

                Divider()

                Text(L10n.moderators)
                    .font(.title2.bold())

                HStack {
                    TextField(
                        L10n.moderatorHandle,
                        text: $moderatorHandle
                    )
                    Button(L10n.addModerator) {
                        let handle = moderatorHandle
                        Task {
                            if await model.setModerator(
                                handle: handle,
                                enabled: true
                            ) {
                                moderatorHandle = ""
                            }
                        }
                    }
                    .disabled(
                        moderatorHandle.isEmpty || model.isWorking
                    )
                }

                ForEach(model.moderators) { moderator in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(moderator.displayName)
                            Text("@\(moderator.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.remove, role: .destructive) {
                            Task {
                                _ = await model.setModerator(
                                    handle: moderator.handle,
                                    enabled: false
                                )
                            }
                        }
                        .disabled(model.isWorking)
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $selectedItem) { item in
            ModerationReviewView(
                appModel: appModel,
                model: model,
                item: item
            )
        }
    }
}

private struct ModerationReviewView: View {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var model: MarketplaceAccountViewModel
    let item: MarketplaceModerationItem
    @State private var compatibility: MarketplaceCompatibility = .compatible
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                ModerationPreviewImage(
                    url: item.previewURL,
                    height: 170
                )
                .frame(width: 250)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title.bold())
                    Text("@\(item.creatorHandle) · v\(item.semanticVersion)")
                        .foregroundStyle(.secondary)
                    Text(item.description)
                        .lineLimit(5)
                    Label(
                        L10n.cursorCount(item.includedRoles.count),
                        systemImage: "cursorarrow.motionlines"
                    )
                    .font(.callout)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(item.includedRoles, id: \.self) { role in
                        Text(role)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            Picker(L10n.compatibility, selection: $compatibility) {
                Text(MarketplaceCompatibility.compatible.displayName)
                    .tag(MarketplaceCompatibility.compatible)
                Text(MarketplaceCompatibility.limited.displayName)
                    .tag(MarketplaceCompatibility.limited)
                Text(MarketplaceCompatibility.incompatible.displayName)
                    .tag(MarketplaceCompatibility.incompatible)
            }

            TextField(L10n.moderationNote, text: $note, axis: .vertical)
                .lineLimit(3...6)

            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.testThemeOnMac)
                            .font(.headline)
                        Text(
                            isTesting
                                ? L10n.themeTestActiveDetail
                                : L10n.themeTestRequired
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isTesting {
                        Button(L10n.stopThemeTest) {
                            Task {
                                _ = await appModel.stopModerationTest()
                            }
                        }
                    } else {
                        Button(L10n.startThemeTest) {
                            Task {
                                _ = await appModel.startModerationTest(item)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Spacer()

            HStack {
                Button(L10n.cancel) {
                    dismiss()
                }
                Spacer()
                Button(L10n.reject, role: .destructive) {
                    Task {
                        guard await appModel.stopModerationTest() else {
                            return
                        }
                        if await model.moderate(
                            item: item,
                            approve: false,
                            compatibility: compatibility,
                            note: note
                        ) {
                            dismiss()
                        }
                    }
                }
                Button(L10n.approve) {
                    Task {
                        guard await appModel.stopModerationTest() else {
                            return
                        }
                        if await model.moderate(
                            item: item,
                            approve: true,
                            compatibility: compatibility,
                            note: note
                        ) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.isWorking
                        || !model.testedVersionIDs.contains(item.id)
                )
            }
        }
        .padding(24)
        .frame(width: 700, height: 650)
        .onDisappear {
            if isTesting {
                Task { _ = await appModel.stopModerationTest() }
            }
        }
    }

    private var isTesting: Bool {
        appModel.moderationTestVersionID == item.versionID
    }
}

private struct ModerationPreviewImage: View {
    let url: URL?
    let height: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.22),
                    Color.purple.opacity(0.13),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
            } else {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor))
        }
        .accessibilityLabel(L10n.themePreview)
    }
}
