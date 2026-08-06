import SwiftUI
import ContactsUI
import DunduKit

/// The screen where you tell Dundu about your businesses. Routing is only as
/// good as what lives here, so the editor has to be pleasant enough to
/// actually fill in. Stored as local JSON, never synced anywhere.
struct ProfileContextView: View {
    @State private var profile = ProfileContext()
    private let store = ProfileContextStore()

    var body: some View {
        List {
            if profile.businesses.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No businesses yet",
                        systemImage: "building.2",
                        description: Text("Add your businesses so Dundu can route new items to the right calendar and list, and fix names Siri mishears.")
                    )
                }
            }

            ForEach($profile.businesses, id: \.name) { $business in
                Section {
                    NavigationLink {
                        BusinessEditView(business: $business, onChange: save)
                    } label: {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text(business.name).font(.headline)
                            Text(summaryLine(business))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                profile.businesses.remove(atOffsets: offsets)
                save()
            }

            Section {
                Button {
                    profile.businesses.append(BusinessContext(
                        name: "New business",
                        calendarRole: CalendarRef.Role.personal.rawValue
                    ))
                    save()
                } label: {
                    Label("Add a business", systemImage: "plus")
                }
            } footer: {
                Text("Stays on this device. Never synced, never uploaded.")
            }
        }
        .navigationTitle("Profile Context")
        .onAppear { profile = store.load() }
    }

    private func summaryLine(_ business: BusinessContext) -> String {
        var parts = [business.calendarRole]
        if !business.people.isEmpty { parts.append("\(business.people.count) people") }
        if !business.keywords.isEmpty { parts.append("\(business.keywords.count) keywords") }
        return parts.joined(separator: " · ")
    }

    private func save() {
        profile.updatedAt = Date()
        try? store.save(profile)
    }
}

// MARK: - Business editor

struct BusinessEditView: View {
    @Binding var business: BusinessContext
    var onChange: () -> Void

    @State private var aliasesText = ""
    @State private var keywordsText = ""
    @State private var showingContactsPicker = false
    @State private var manualPersonName = ""

    var body: some View {
        Form {
            Section("Business") {
                TextField("Name", text: $business.name)
                TextField("Aliases, comma separated", text: $aliasesText)
                    .autocorrectionDisabled()
            }

            Section {
                Picker("Calendar", selection: $business.calendarRole) {
                    Text("Personal").tag(CalendarRef.Role.personal.rawValue)
                    Text("Work A").tag(CalendarRef.Role.workA.rawValue)
                    Text("Work B").tag(CalendarRef.Role.workB.rawValue)
                }
            } footer: {
                Text("Routing targets this role, not calendar names — names change.")
            }

            Section("Keywords") {
                TextField("investor, filing, creator ops…", text: $keywordsText)
                    .autocorrectionDisabled()
            }

            Section {
                ForEach(business.people, id: \.displayName) { person in
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        Text(person.displayName)
                        if !person.aliases.isEmpty {
                            Text(person.aliases.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    business.people.remove(atOffsets: offsets)
                    onChange()
                }

                Button {
                    showingContactsPicker = true
                } label: {
                    Label("Add from Contacts", systemImage: "person.crop.circle.badge.plus")
                }

                HStack {
                    TextField("Or type a name", text: $manualPersonName)
                        .onSubmit(addManualPerson)
                    Button("Add", action: addManualPerson)
                        .disabled(manualPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("People")
            } footer: {
                Text("Names get phonetic keys so misheard dictation (\u{201C}Vivien\u{201D} for Vivian) can be caught and fixed.")
            }
        }
        .navigationTitle(business.name)
        .onAppear {
            aliasesText = business.aliases.joined(separator: ", ")
            keywordsText = business.keywords.joined(separator: ", ")
        }
        .onDisappear(perform: commitTextFields)
        .sheet(isPresented: $showingContactsPicker) {
            ContactsPicker { contacts in
                for contact in contacts {
                    let name = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    guard !name.isEmpty,
                          !business.people.contains(where: { $0.displayName == name })
                    else { continue }
                    let nickname = contact.nickname.isEmpty ? nil : contact.nickname
                    business.people.append(PersonRef(
                        displayName: name,
                        aliases: nickname.map { [$0] } ?? [],
                        phoneticKeys: Phonetics.nameKeys(for: ([name] + (nickname.map { [$0] } ?? [])).joined(separator: " ")),
                        affiliation: business.name
                    ))
                }
                onChange()
            }
        }
        .onChange(of: business.calendarRole) { onChange() }
    }

    private func addManualPerson() {
        let name = manualPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !business.people.contains(where: { $0.displayName == name }) else { return }
        business.people.append(PersonRef(
            displayName: name,
            phoneticKeys: Phonetics.nameKeys(for: name),
            affiliation: business.name
        ))
        manualPersonName = ""
        onChange()
    }

    private func commitTextFields() {
        business.aliases = aliasesText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        business.keywords = keywordsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onChange()
    }
}

// MARK: - Contacts picker

/// CNContactPickerViewController runs out of process, so seeding names from
/// Contacts needs no permission prompt and Dundu never reads the database.
struct ContactsPicker: UIViewControllerRepresentable {
    var onPick: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([CNContact]) -> Void
        init(onPick: @escaping ([CNContact]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onPick(contacts)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick([contact])
        }
    }
}
