// SPDX-License-Identifier: GPL-3.0-or-later
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var selection: PhotosPickerItem?
    @State private var photos = false
    @State private var files = false
    @State private var exporting = false
    @State private var about = false
    @State private var fullScreen = false
    @State private var tab = "显影"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    canvas
                    if model.sourceURL != nil {
                        stockRow
                        VStack(spacing: 20) {
                            Picker("工具", selection: $tab) {
                                Text("显影").tag("显影"); Text("效果").tag("效果"); Text("构图").tag("构图")
                            }.pickerStyle(.segmented)
                            controls
                        }.padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 20) {
                            Text("从照片或文件导入，在本机完成显影。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            importButtons
                            Button("打开色彩测试图") { Task { await model.demo() } }
                                .font(.footnote).foregroundStyle(.secondary)
                        }.padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
                .disabled(model.isExporting)
            }
            .background(Color(white: 0.055))
            .navigationTitle("Grainroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { about = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("关于与许可证")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { photos = true } label: { Label("从照片导入", systemImage: "photo") }
                        Button { files = true } label: { Label("从文件导入", systemImage: "folder") }
                        Button("重置调整", role: .destructive) { model.reset() }.disabled(model.sourceURL == nil)
                    } label: { Image(systemName: "plus") }.accessibilityLabel("导入照片")
                    .disabled(model.isExporting)
                }
                ToolbarItem(placement: .bottomBar) {
                    if model.sourceURL != nil {
                        Button { exporting = true } label: {
                            Label("导出照片", systemImage: "square.and.arrow.up").fontWeight(.semibold)
                        }.disabled(model.photo == nil || model.isRendering || model.isExporting)
                    }
                }
            }
        }
        .accessibilityHidden(fullScreen)
        // The menu disappears after a tap. Present from the persistent editor
        // so the photo picker's presentation host survives that dismissal.
        .photosPicker(isPresented: $photos, selection: $selection, matching: .images, preferredItemEncoding: .current)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let photo = try await item.loadTransferable(type: PickedPhoto.self) else {
                        throw PhotoFailure.message("无法读取这张照片，请试试从文件导入原图。")
                    }
                    await model.importPhoto(photo.url, title: photo.title, removeTemporary: true)
                } catch { model.error = error.localizedDescription }
                selection = nil
            }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.image, .rawImage]) { result in
            switch result {
            case .success(let url): Task { await model.importPhoto(url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $exporting) { ExportView(model: model) }
        .sheet(isPresented: $about) { AboutView() }
        .fullScreenCover(isPresented: $fullScreen) {
            if let image = model.photo { FullScreenPhotoView(image: image, original: model.original) }
        }
        .onChange(of: model.sourceURL) { _, _ in fullScreen = false }
        .alert("未能完成", isPresented: Binding(get: { model.error != nil && !exporting }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var importButtons: some View {
        VStack(spacing: 12) {
            Button { photos = true } label: {
                Label("从照片导入", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button { files = true } label: { Label("从文件导入 RAW 或照片", systemImage: "folder").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private var canvas: some View {
        VStack(spacing: 12) {
            ZStack {
                if let image = model.photo {
                    PhotoPreview(image: image, original: model.original, zoomEnabled: false) { fullScreen = true }
                        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "camera.aperture").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(.tint)
                        Text("把照片带进暗房").font(.title3.weight(.medium))
                    }.frame(maxWidth: .infinity, minHeight: 260)
                }
                if model.isRendering {
                    ProgressView().padding(14).background(.ultraThinMaterial, in: Circle())
                }
            }
            if model.sourceURL != nil {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title).font(.caption).lineLimit(1)
                        Text(model.isRendering ? "显影中…" : "\(model.isRAW ? "RAW · " : "")预览 \(model.dimensions)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { fullScreen = true } label: {
                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.medium))
                    }.buttonStyle(.bordered).disabled(model.photo == nil)
                        .accessibilityLabel("全屏查看照片")
                }.padding(.horizontal, 16)
            }
        }
    }

    private var stockRow: some View {
        VStack(spacing: 16) {
            StockStrip(title: "胶片", symbol: "film", stocks: model.library.films, selected: model.settings.film) {
                model.chooseFilm($0)
            }
            if model.library.stock(model.settings.film)?.isPositive != true {
                StockStrip(title: "相纸", symbol: "square.stack",
                           stocks: model.library.papers(for: model.library.stock(model.settings.film)), selected: model.settings.paper) {
                    model.settings.paper = $0.id; model.schedule()
                }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 22) {
            if tab == "显影" {
                adjustment("胶片曝光", value: $model.settings.exposure, range: -3...3, unit: "EV")
                if model.library.stock(model.settings.film)?.isPositive != true {
                    adjustment("印相明度", value: $model.settings.printBrightness, range: -2...2, unit: "EV")
                }
                if model.isRAW {
                    Toggle("相机白平衡", isOn: Binding(get: { model.settings.decode.whiteBalance == .asShot }, set: {
                        model.settings.decode.whiteBalance = $0 ? .asShot : .custom; model.schedule()
                    }))
                    if model.settings.decode.whiteBalance != .asShot {
                        adjustment("色温", value: $model.settings.decode.temperature, range: 2500...10000, unit: "K", digits: 0)
                        adjustment("色调", value: $model.settings.decode.tint, range: -100...100)
                    }
                }
            } else if tab == "效果" {
                adjustment("颗粒", value: $model.settings.grain, range: 0...2)
                adjustment("光晕", value: $model.settings.halation, range: 0...4)
            } else {
                Picker("居中裁剪", selection: $model.settings.crop) {
                    ForEach(CropRatio.allCases) { Text($0.rawValue).tag($0) }
                }.onChange(of: model.settings.crop) { _, _ in model.schedule() }
                HStack(spacing: 16) {
                    Button { model.settings.quarterTurns = (model.settings.quarterTurns + 1) % 4; model.schedule() } label: {
                        Label("旋转", systemImage: "rotate.right")
                    }
                    Button { model.settings.mirror.toggle(); model.schedule() } label: {
                        Label("镜像", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    }
                }.buttonStyle(.bordered)
                Text("按所选比例居中裁剪，原始文件保留。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func adjustment(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "", digits: Int = 2) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(digits)))) \(unit)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).onChange(of: value.wrappedValue) { _, _ in model.schedule() }
                .accessibilityLabel(name)
        }
    }
}

struct StockStrip: View {
    let title: String
    let symbol: String
    let stocks: [FilmStock]
    let selected: String
    let choose: (FilmStock) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if stocks.count > 2 { Text("滑动选择").font(.caption2) }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stocks) { stock in
                            Button { choose(stock) } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(stock.name).lineLimit(2).multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                        .opacity(stock.id == selected ? 1 : 0)
                                }
                                .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                .frame(width: 142, height: 32, alignment: .leading).padding(10)
                                .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(.tint.opacity(stock.id == selected ? 1 : 0), lineWidth: 1.5)
                                }
                            }
                            .buttonStyle(.plain).id(stock.id)
                            .accessibilityLabel("\(title)：\(stock.name)")
                            .accessibilityAddTraits(stock.id == selected ? .isSelected : [])
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
                .onChange(of: selected) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                }
            }
        }
    }
}

struct ExportView: View {
    @Bindable var model: EditorModel
    @State private var kind = ExportKind.jpeg
    @State private var edge = 2560
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("文件") {
                    Picker("格式", selection: $kind) { ForEach(ExportKind.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("最长边", selection: $edge) {
                        Text("1600 像素").tag(1600); Text("2560 像素").tag(2560); Text("4096 像素").tag(4096)
                    }
                    Text("sRGB · 最多 1200 万像素 · 不放大原图").font(.caption).foregroundStyle(.secondary)
                }.disabled(model.isExporting)
                Section {
                    Button { Task { await model.export(edge: edge, kind: kind) } } label: {
                        HStack { Text("生成导出文件"); Spacer(); if model.isExporting { ProgressView() } }
                    }.disabled(model.isExporting)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }
                if let url = model.exportURL {
                    Section("导出完成") {
                        ShareLink(item: url) { Label("分享或保存到文件", systemImage: "square.and.arrow.up") }
                        Button { Task { await model.saveToPhotos() } } label: { Label("保存到照片", systemImage: "photo.badge.arrow.down") }
                        if let notice = model.notice { Text(notice).foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("导出照片").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { dismiss() }.disabled(model.isExporting) }
                .interactiveDismissDisabled(model.isExporting)
                .onChange(of: kind) { _, _ in model.exportURL = nil }
                .onChange(of: edge) { _, _ in model.exportURL = nil }
        }.preferredColorScheme(.dark)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private let licenses = [
        ("GNU GPL v3 — 应用与渲染引擎", "SpektraLab-GPL-3.0.txt"),
        ("CC BY-SA 4.0 — 胶片数据与 LUT", "Profiles-and-LUTs-CC-BY-SA-4.0.txt"),
        ("数据改动记录", "Profiles-and-LUTs-CHANGELOG.txt"),
        ("Apache 2.0 — metal-cpp", "metal-cpp-Apache-2.0.txt"),
        ("产品数据来源", "PRODUCT_PROFILES_NOTICE.md"),
    ]
    var body: some View {
        NavigationStack {
            List {
                Section("Grainroom 0.1 · 非官方 iOS 移植") {
                    Text("基于 SpektraLab 的 C++/Metal 引擎和 Andrea Volpato 的 spektrafilm。胶片模型与原始数据归原作者所有；iOS 界面和适配修改以 GPL-3.0-or-later 发布。")
                    Link("Grainroom 移植源码", destination: URL(string: "https://github.com/RayOnFire/SpektraLab/tree/ios/grainroom-source-port/ios")!)
                    Link("SpektraLab · Hanze Qiu", destination: URL(string: "https://github.com/JamesQiu2005/SpektraLab")!)
                    Link("spektrafilm · Andrea Volpato", destination: URL(string: "https://github.com/andreavolpato/spektrafilm")!)
                    Text("原始胶片/相纸配置及派生 LUT 采用 CC BY-SA 4.0；额外黑白配置及数据来源见随附说明。本项目与原作者或胶片厂商没有官方关联。")
                }
                Section("许可证与署名") {
                    ForEach(licenses, id: \.1) { item in
                        NavigationLink(item.0) {
                            ScrollView { Text(license(item.1)).font(.caption.monospaced()).textSelection(.enabled).padding() }
                                .navigationTitle("许可证").navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
            }.navigationTitle("关于 Grainroom").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { dismiss() } }
        }.preferredColorScheme(.dark)
    }
    private func license(_ filename: String) -> String {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "Resources/Licenses"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可证文件缺失，请重新构建。" }
        return text
    }
}
