import AppKit
import Foundation

struct ToolResult { let success: Bool; let output: String }

enum SystemToolRegistry {
    static let toolNames: [String] = [
        "open_application", "open_url", "open_item", "list_directory", "file_info", "search_files",
        "read_text_file", "write_text_file", "append_text_file", "replace_text_in_file", "file_exists", "create_directory", "move_item", "copy_item",
        "delete_item", "get_clipboard", "set_clipboard", "system_info", "list_processes",
        "run_shell_command", "run_applescript", "accessibility_status", "accessibility_request", "ui_snapshot", "ui_focus_app", "ui_click", "ui_set_value", "ui_type_text", "ui_key", "ui_click_point"
    ]

    static let definitions: [[String: Any]] = [
        tool("open_application", "Ouvre une application macOS.", ["name": str("Nom ou bundle identifier")], ["name"]),
        tool("open_url", "Ouvre une URL.", ["url": str("URL")], ["url"]),
        tool("open_item", "Ouvre un fichier ou dossier local avec macOS.", ["path": str("Chemin absolu ou ~/...")], ["path"]),
        tool("list_directory", "Liste réellement le contenu d'un dossier avec type, taille, dates de création et modification. Peut trier par modification pour trouver le fichier le plus récent.", ["path": str("Dossier, ex: ~/Downloads"), "sort": str("name, modified_desc, modified_asc, created_desc, size_desc"), "limit": str("Nombre maximal de résultats, ex: 100")], ["path"]),
        tool("file_info", "Retourne les métadonnées détaillées d'un fichier ou dossier.", ["path": str("Chemin")], ["path"]),
        tool("search_files", "Recherche récursivement des fichiers/dossiers par nom depuis un dossier choisi.", ["query": str("Texte à rechercher"), "root": str("Racine, ex: ~ ou ~/Downloads"), "limit": str("Maximum de résultats")], ["query"]),
        tool("read_text_file", "Lit un fichier texte local.", ["path": str("Chemin"), "max_bytes": str("Taille maximale à lire")], ["path"]),
        tool("write_text_file", "Crée ou remplace un fichier texte. À privilégier pour écrire du code.", ["path": str("Chemin"), "content": str("Contenu complet")], ["path", "content"]),
        tool("replace_text_in_file", "Remplace exactement un fragment dans un fichier texte existant.", ["path": str("Chemin"), "old": str("Texte exact à remplacer"), "new": str("Nouveau texte")], ["path", "old", "new"]),
        tool("file_exists", "Vérifie si un fichier ou dossier existe.", ["path": str("Chemin")], ["path"]),
        tool("append_text_file", "Ajoute du texte à la fin d'un fichier.", ["path": str("Chemin"), "content": str("Contenu")], ["path", "content"]),
        tool("create_directory", "Crée un dossier.", ["path": str("Chemin")], ["path"]),
        tool("move_item", "Déplace ou renomme un fichier/dossier.", ["source": str("Source"), "destination": str("Destination")], ["source", "destination"]),
        tool("copy_item", "Copie un fichier/dossier.", ["source": str("Source"), "destination": str("Destination")], ["source", "destination"]),
        tool("delete_item", "Supprime un fichier/dossier. Action destructive.", ["path": str("Chemin")], ["path"]),
        tool("get_clipboard", "Lit le presse-papiers.", [:], []),
        tool("set_clipboard", "Modifie le presse-papiers.", ["text": str("Texte")], ["text"]),
        tool("system_info", "Retourne des informations sur le Mac.", [:], []),
        tool("list_processes", "Liste les applications ouvertes.", [:], []),
        tool("run_shell_command", "Exécute une commande zsh locale et retourne stdout/stderr. À utiliser lorsque les outils spécialisés ne suffisent pas.", ["command": str("Commande zsh"), "working_directory": str("Dossier de travail optionnel")], ["command"]),
        tool("run_applescript", "Exécute un AppleScript pour automatiser macOS et les applications autorisées par le système.", ["script": str("Source AppleScript")], ["script"]),
        tool("accessibility_status", "Vérifie si Lumo a l'autorisation macOS Accessibilité nécessaire au contrôle visuel des apps.", [:], []),
        tool("accessibility_request", "Affiche la demande macOS d'autorisation Accessibilité pour Lumo.", [:], []),
        tool("ui_snapshot", "Observe l'arbre Accessibility d'une application ouverte avant d'agir. Retourne rôles, titres et valeurs des contrôles visibles.", ["app": str("Nom ou bundle id de l'application"), "max_depth": str("Profondeur 1-8"), "max_items": str("Maximum 10-500")], ["app"]),
        tool("ui_focus_app", "Place une application ouverte au premier plan.", ["app": str("Nom ou bundle id")], ["app"]),
        tool("ui_click", "Clique un contrôle via macOS Accessibility. Utiliser ui_snapshot avant. Les filtres vides sont ignorés.", ["app": str("Application"), "role": str("Rôle AX ex AXButton"), "title": str("Titre contient"), "value": str("Valeur contient"), "index": str("Index si plusieurs résultats, défaut 0")], ["app"]),
        tool("ui_set_value", "Saisit une valeur directement dans un champ accessible. Utiliser ui_snapshot avant.", ["app": str("Application"), "role": str("Rôle AX, ex AXTextField"), "title": str("Titre contient"), "current_value": str("Valeur actuelle contient"), "value": str("Nouvelle valeur"), "index": str("Index, défaut 0")], ["app","value"]),
        tool("ui_type_text", "Tape du texte dans l'élément actuellement focalisé, comme un clavier réel.", ["text": str("Texte à saisir")], ["text"]),
        tool("ui_key", "Envoie une touche ou raccourci clavier. Touches: return, tab, space, escape, delete, flèches, a/c/v/x/s/o/w/q.", ["key": str("Touche"), "modifiers": str("command shift option control")], ["key"]),
        tool("ui_click_point", "Solution de repli: clique à des coordonnées écran absolues lorsque Accessibility ne fournit aucun contrôle exploitable.", ["x": str("Coordonnée X"), "y": str("Coordonnée Y")], ["x","y"])
    ]

    static func risk(for name: String) -> ToolRisk {
        ["write_text_file", "append_text_file", "replace_text_in_file", "create_directory", "move_item", "copy_item", "delete_item", "set_clipboard", "run_shell_command", "run_applescript", "accessibility_request", "ui_click", "ui_set_value", "ui_type_text", "ui_key", "ui_click_point"].contains(name) ? .confirmation : .safe
    }

    static func summary(name: String, args: [String: AnyCodable]) -> String {
        switch name {
        case "write_text_file": return "Écrire dans \(s(args,"path"))"
        case "replace_text_in_file": return "Modifier \(s(args,"path"))"
        case "file_exists": return "Vérifier \(s(args,"path"))"
        case "append_text_file": return "Modifier \(s(args,"path"))"
        case "create_directory": return "Créer le dossier \(s(args,"path"))"
        case "move_item": return "Déplacer \(s(args,"source")) vers \(s(args,"destination"))"
        case "copy_item": return "Copier \(s(args,"source")) vers \(s(args,"destination"))"
        case "delete_item": return "Supprimer \(s(args,"path"))"
        case "set_clipboard": return "Remplacer le presse-papiers"
        case "run_shell_command": return "Exécuter : \(s(args,"command"))"
        case "run_applescript": return "Exécuter un AppleScript"
        case "accessibility_request": return "Demander l’accès Accessibilité macOS"
        case "ui_click": return "Cliquer dans \(s(args,"app"))"
        case "ui_set_value": return "Saisir du texte dans \(s(args,"app"))"
        case "ui_type_text": return "Saisir du texte au clavier"
        case "ui_key": return "Envoyer la touche \(s(args,"key"))"
        case "ui_click_point": return "Cliquer à l’écran (\(s(args,"x")), \(s(args,"y")))"
        default: return name
        }
    }

    static func execute(name: String, args: [String: AnyCodable]) -> ToolResult {
        let fm = FileManager.default
        func path(_ key: String) -> String { NSString(string: s(args,key)).expandingTildeInPath }
        func dateString(_ date: Date?) -> String { guard let date else { return "-" }; return ISO8601DateFormatter().string(from: date) }
        func metadata(_ url: URL) -> String {
            let keys: Set<URLResourceKey> = [.isDirectoryKey,.fileSizeKey,.creationDateKey,.contentModificationDateKey,.isHiddenKey,.contentTypeKey]
            let v = try? url.resourceValues(forKeys: keys)
            return "\(v?.isDirectory == true ? "DIR" : "FILE")\t\(url.lastPathComponent)\tpath=\(url.path)\tsize=\(v?.fileSize ?? 0)\tcreated=\(dateString(v?.creationDate))\tmodified=\(dateString(v?.contentModificationDate))"
        }
        do {
            switch name {
            case "open_application":
                let n = s(args,"name")
                if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier:n) { NSWorkspace.shared.openApplication(at:u,configuration:.init()); return .init(success:true,output:"Application ouverte: \(n)") }
                let dirs = ["/Applications", "/System/Applications", NSString(string:"~/Applications").expandingTildeInPath]
                for dir in dirs {
                    let candidates = (try? fm.contentsOfDirectory(atPath:dir))?.filter { $0.localizedCaseInsensitiveContains(n) && $0.hasSuffix(".app") } ?? []
                    if let first = candidates.first { NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:dir).appendingPathComponent(first),configuration:.init()); return .init(success:true,output:"Application ouverte: \(first)") }
                }
                return .init(success:false,output:"Application introuvable: \(n)")
            case "open_url":
                guard let u = URL(string:s(args,"url")) else { return .init(success:false,output:"URL invalide") }
                return .init(success:NSWorkspace.shared.open(u),output:"URL ouverte")
            case "open_item":
                let p = path("path"); guard fm.fileExists(atPath:p) else { return .init(success:false,output:"Introuvable: \(p)") }
                return .init(success:NSWorkspace.shared.open(URL(fileURLWithPath:p)),output:"Ouvert: \(p)")
            case "list_directory":
                let p = path("path"); var urls = try fm.contentsOfDirectory(at:URL(fileURLWithPath:p), includingPropertiesForKeys:[.isDirectoryKey,.fileSizeKey,.creationDateKey,.contentModificationDateKey], options:[])
                let sort = s(args,"sort"); let limit = max(1, min(Int(s(args,"limit")) ?? 200, 2000))
                func values(_ u:URL) -> URLResourceValues? { try? u.resourceValues(forKeys:[.creationDateKey,.contentModificationDateKey,.fileSizeKey]) }
                switch sort {
                case "modified_desc": urls.sort { (values($0)?.contentModificationDate ?? .distantPast) > (values($1)?.contentModificationDate ?? .distantPast) }
                case "modified_asc": urls.sort { (values($0)?.contentModificationDate ?? .distantPast) < (values($1)?.contentModificationDate ?? .distantPast) }
                case "created_desc": urls.sort { (values($0)?.creationDate ?? .distantPast) > (values($1)?.creationDate ?? .distantPast) }
                case "size_desc": urls.sort { (values($0)?.fileSize ?? 0) > (values($1)?.fileSize ?? 0) }
                default: urls.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                }
                return .init(success:true,output:urls.prefix(limit).map(metadata).joined(separator:"\n"))
            case "file_info":
                let u = URL(fileURLWithPath:path("path")); guard fm.fileExists(atPath:u.path) else { return .init(success:false,output:"Introuvable: \(u.path)") }; return .init(success:true,output:metadata(u))
            case "search_files":
                let q = s(args,"query").lowercased(); let rootText = s(args,"root"); let root = rootText.isEmpty ? fm.homeDirectoryForCurrentUser : URL(fileURLWithPath:NSString(string:rootText).expandingTildeInPath); let limit = max(1,min(Int(s(args,"limit")) ?? 100,1000))
                let e = fm.enumerator(at:root,includingPropertiesForKeys:[.isDirectoryKey,.contentModificationDateKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]); var found:[String] = []
                while let u = e?.nextObject() as? URL, found.count < limit { if u.lastPathComponent.lowercased().contains(q) { found.append(metadata(u)) } }
                return .init(success:true,output:found.isEmpty ? "Aucun résultat." : found.joined(separator:"\n"))
            case "read_text_file":
                let maxBytes = max(1, min(Int(s(args,"max_bytes")) ?? 5_000_000, 50_000_000)); let data = try Data(contentsOf:URL(fileURLWithPath:path("path")),options:.mappedIfSafe); guard data.count <= maxBytes else { return .init(success:false,output:"Fichier trop volumineux (\(data.count) octets).") }; return .init(success:true,output:String(data:data,encoding:.utf8) ?? "Fichier non UTF-8")
            case "write_text_file":
                let p = path("path")
                let expected = s(args,"content")
                let url = URL(fileURLWithPath:p)
                try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                try expected.write(to:url,atomically:true,encoding:.utf8)
                guard fm.fileExists(atPath:p) else { return .init(success:false,output:"Échec de vérification: le fichier n'existe pas après écriture: \(p)") }
                let data = try Data(contentsOf:url)
                guard let actual = String(data:data,encoding:.utf8) else { return .init(success:false,output:"Échec de vérification UTF-8: \(p)") }
                guard actual == expected else { return .init(success:false,output:"Échec de vérification: le contenu relu diffère du contenu demandé (\(data.count) octets): \(p)") }
                return .init(success:true,output:"Fichier écrit et vérifié: \(p) · \(data.count) octets")
            case "append_text_file":
                let p = path("path"); let data = s(args,"content").data(using:.utf8) ?? Data(); if !fm.fileExists(atPath:p) { fm.createFile(atPath:p,contents:data) } else { let h = try FileHandle(forWritingTo:URL(fileURLWithPath:p)); try h.seekToEnd(); try h.write(contentsOf:data); try h.close() }; return .init(success:true,output:"Texte ajouté: \(p)")
            case "replace_text_in_file":
                let p = path("path"); let old = s(args,"old"); let new = s(args,"new"); let current = try String(contentsOfFile:p,encoding:.utf8); guard current.contains(old) else { return .init(success:false,output:"Fragment introuvable dans \(p)") }; let updated = current.replacingOccurrences(of:old,with:new); try updated.write(toFile:p,atomically:true,encoding:.utf8); return .init(success:true,output:"Fichier modifié: \(p)")
            case "file_exists":
                let p = path("path"); var isDir: ObjCBool = false; let exists = fm.fileExists(atPath:p,isDirectory:&isDir); return .init(success:true,output:exists ? "Existe: \(p) (\(isDir.boolValue ? "dossier" : "fichier"))" : "Absent: \(p)")
            case "create_directory": try fm.createDirectory(atPath:path("path"),withIntermediateDirectories:true); return .init(success:true,output:"Dossier créé")
            case "move_item": try fm.moveItem(atPath:path("source"),toPath:path("destination")); return .init(success:true,output:"Élément déplacé")
            case "copy_item": try fm.copyItem(atPath:path("source"),toPath:path("destination")); return .init(success:true,output:"Élément copié")
            case "delete_item": try fm.removeItem(atPath:path("path")); return .init(success:true,output:"Élément supprimé")
            case "get_clipboard": return .init(success:true,output:NSPasteboard.general.string(forType:.string) ?? "Presse-papiers vide")
            case "set_clipboard": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s(args,"text"),forType:.string); return .init(success:true,output:"Presse-papiers mis à jour")
            case "system_info": let p = ProcessInfo.processInfo; return .init(success:true,output:"macOS \(p.operatingSystemVersionString); hôte \(p.hostName); processeurs \(p.processorCount); mémoire \(p.physicalMemory/1_073_741_824) Go; home \(fm.homeDirectoryForCurrentUser.path)")
            case "list_processes": return .init(success:true,output:NSWorkspace.shared.runningApplications.compactMap{$0.localizedName}.sorted().joined(separator:"\n"))
            case "run_shell_command":
                let process = Process(); process.executableURL = URL(fileURLWithPath:"/bin/zsh"); process.arguments = ["-lc", s(args,"command")]; let wd = s(args,"working_directory"); if !wd.isEmpty { process.currentDirectoryURL = URL(fileURLWithPath:NSString(string:wd).expandingTildeInPath) }
                let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe; try process.run(); process.waitUntilExit(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); let out = String(data:data,encoding:.utf8) ?? ""; return .init(success:process.terminationStatus == 0,output:"exit=\(process.terminationStatus)\n\(out.prefix(100_000))")
            case "run_applescript":
                var error: NSDictionary?; let result = NSAppleScript(source:s(args,"script"))?.executeAndReturnError(&error); if let error { return .init(success:false,output:"AppleScript: \(error)") }; return .init(success:true,output:result?.stringValue ?? "AppleScript exécuté")
            case "accessibility_status": return .init(success:true, output: AccessibilityController.isTrusted() ? "Accessibilité autorisée." : "Accessibilité non autorisée.")
            case "accessibility_request": return AccessibilityController.requestPermission()
            case "ui_snapshot": return AccessibilityController.snapshot(app:s(args,"app"), maxDepth:Int(s(args,"max_depth")) ?? 5, maxItems:Int(s(args,"max_items")) ?? 180)
            case "ui_focus_app": return AccessibilityController.focusApp(s(args,"app"))
            case "ui_click": return AccessibilityController.click(app:s(args,"app"), role:s(args,"role"), title:s(args,"title"), value:s(args,"value"), index:Int(s(args,"index")) ?? 0)
            case "ui_set_value": return AccessibilityController.setValue(app:s(args,"app"), role:s(args,"role"), title:s(args,"title"), currentValue:s(args,"current_value"), value:s(args,"value"), index:Int(s(args,"index")) ?? 0)
            case "ui_type_text": return AccessibilityController.typeText(s(args,"text"))
            case "ui_key": return AccessibilityController.key(s(args,"key"), modifiers:s(args,"modifiers"))
            case "ui_click_point": return AccessibilityController.clickPoint(x:Double(s(args,"x")) ?? 0, y:Double(s(args,"y")) ?? 0)
            default: return .init(success:false,output:"Outil inconnu")
            }
        } catch { return .init(success:false,output:error.localizedDescription) }
    }

    private static func s(_ a:[String:AnyCodable],_ k:String)->String { a[k]?.string ?? "" }
    private static func str(_ d:String)->[String:Any] { ["type":"string","description":d] }
    private static func tool(_ n:String,_ d:String,_ props:[String:Any],_ req:[String])->[String:Any] { ["name":n,"description":d,"input_schema":["type":"object","properties":props,"required":req]] }
}
