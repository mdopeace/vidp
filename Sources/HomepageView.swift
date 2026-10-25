import AppKit

private final class NavigationButtonContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class HomepageView: NSView {
    private enum Section: Int, CaseIterable {
        case recents
        case home
        case movies
        case series
        case others

        var title: String {
            switch self {
            case .recents: "Recents"
            case .home: "Home"
            case .movies: "Movies"
            case .series: "Series"
            case .others: "Others"
            }
        }

        var symbol: String {
            switch self {
            case .recents: "clock"
            case .home: "house"
            case .movies: "film"
            case .series: "tv"
            case .others: "square.grid.2x2"
            }
        }

        var emptyTitle: String {
            switch self {
            case .recents: "No recent videos"
            case .home: ""
            case .movies: "No movies yet"
            case .series: "No series yet"
            case .others: "No other videos yet"
            }
        }

        var emptySubtitle: String {
            switch self {
            case .recents: "Videos you open will appear here."
            case .home: ""
            case .movies, .series, .others: "Open a video to start watching."
            }
        }
    }

    private let sidebarWidth: CGFloat = 200
    private let playerContainer: NSView
    private let sidebar = NSVisualEffectView()
    private let separator = NSView()
    private let contentArea = NSView()
    private let emptyStateView = NSView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptySubtitle = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
    private var navigationIcons: [NSImageView] = []
    private var navigationTitles: [NSTextField] = []
    private var selectedSection = Section.home
    private var isPlaybackActive = false
    private var sidebarContentConstraint: NSLayoutConstraint!
    private var playerContentConstraint: NSLayoutConstraint!

    init(playerContainer: NSView) {
        self.playerContainer = playerContainer
        super.init(frame: .zero)

        sidebar.material = .sidebar
        sidebar.state = .active
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar)

        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let background = NSVisualEffectView()
        background.material = .windowBackground
        background.state = .active
        background.blendingMode = .behindWindow
        background.translatesAutoresizingMaskIntoConstraints = false
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentArea)
        contentArea.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentArea.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        sidebarContentConstraint = contentArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor)
        playerContentConstraint = contentArea.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentArea.topAnchor.constraint(equalTo: topAnchor),
            contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarContentConstraint,
        ])

        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(playerContainer)
        NSLayoutConstraint.activate([
            playerContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            playerContainer.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            playerContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            playerContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(emptyStateView)
        emptyIcon.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 38, weight: .regular))
        emptyIcon.contentTintColor = .secondaryLabelColor
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyTitle.font = .systemFont(ofSize: 20, weight: .medium)
        emptyTitle.textColor = .labelColor
        emptySubtitle.font = .systemFont(ofSize: 13)
        emptySubtitle.textColor = .secondaryLabelColor
        let emptyStack = NSStackView(views: [emptyIcon, emptyTitle, emptySubtitle])
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 8
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            emptyStateView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: contentArea.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
        ])

        let navigation = NSStackView()
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.distribution = .fill
        navigation.spacing = 4
        for section in Section.allCases {
            let button = NSButton(title: section.title, target: self, action: #selector(sectionTapped(_:)))
            button.tag = section.rawValue
            button.attributedTitle = NSAttributedString(
                string: section.title,
                attributes: [.foregroundColor: NSColor.clear])
            button.isBordered = false
            button.setButtonType(.toggle)
            button.wantsLayer = true
            button.layer?.cornerRadius = 9
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true

            let content = NavigationButtonContentView()
            content.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                content.topAnchor.constraint(equalTo: button.topAnchor),
                content.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])

            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
            icon.imageScaling = .scaleProportionallyDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(icon)

            let title = NSTextField(labelWithString: section.title)
            title.font = .systemFont(ofSize: 14)
            title.textColor = .labelColor
            title.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(title)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 24),
                icon.heightAnchor.constraint(equalToConstant: 24),
                title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                title.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8),
            ])

            buttons.append(button)
            navigationIcons.append(icon)
            navigationTitles.append(title)
            navigation.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
        }

        navigation.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(navigation)
        NSLayoutConstraint.activate([
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 40),
        ])

        updateSelectedSection()
        updateContentVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func setPlaybackActive(_ active: Bool) {
        isPlaybackActive = active
        updateContentVisibility()
    }

    @objc private func sectionTapped(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        selectedSection = section
        updateSelectedSection()
        updateContentVisibility()
    }

    private func updateSelectedSection() {
        for section in Section.allCases {
            let button = buttons[section.rawValue]
            let icon = navigationIcons[section.rawValue]
            let title = navigationTitles[section.rawValue]
            let isSelected = section == selectedSection
            button.state = isSelected ? .on : .off
            title.font = .systemFont(ofSize: 14)
            title.textColor = .labelColor
            icon.contentTintColor = .systemBlue
            button.layer?.backgroundColor = isSelected
                ? NSColor(white: 1, alpha: 0.14).cgColor
                : NSColor.clear.cgColor
        }

        emptyIcon.image = NSImage(systemSymbolName: selectedSection.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 38, weight: .regular))
        emptyTitle.stringValue = selectedSection.emptyTitle
        emptySubtitle.stringValue = selectedSection.emptySubtitle
    }

    private func updateContentVisibility() {
        let showPlayer = isPlaybackActive || selectedSection == .home
        sidebar.isHidden = isPlaybackActive
        separator.isHidden = isPlaybackActive
        if isPlaybackActive {
            if sidebarContentConstraint.isActive {
                sidebarContentConstraint.isActive = false
            }
            if !playerContentConstraint.isActive {
                playerContentConstraint.isActive = true
            }
        } else {
            if playerContentConstraint.isActive {
                playerContentConstraint.isActive = false
            }
            if !sidebarContentConstraint.isActive {
                sidebarContentConstraint.isActive = true
            }
        }
        playerContainer.isHidden = !showPlayer
        emptyStateView.isHidden = showPlayer
    }
}
