import SwiftUI
import UniformTypeIdentifiers

struct FocusReviewView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject private var histogram = HistogramManager.shared
    @ObservedObject private var blockManager = BlockProgressManager.shared
    @ObservedObject private var plants = PlantJournal.shared

    @State private var range: FocusReviewRange = .week
    @State private var historyPage: FocusReviewHistoryPage?
    @State private var selectedKey: String?
    @State private var exportDocument: FocusReviewCSV?
    @State private var showExport = false
    @State private var exportError: String?
    @State private var showClearConfirm = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: timeline.date)
            let review = report(today: today, calendar: calendar)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.pageSpacing) {
                    ThemedPageHeader(title: "专注复盘", subtitle: "回看每天的番茄、时间块和种植记录。",
                                     symbol: "chart.bar.xaxis")
                    periodSummary(review, today: today, calendar: calendar)
                    if review.hasRecords, let day = selectedDay(in: review) {
                        trend(review, selected: day, calendar: calendar)
                        dayDetail(day)
                    } else {
                        ThemedEmptyState(symbol: "chart.bar.xaxis", title: "这段时间还没有专注记录",
                                         message: "所选日期内没有番茄、时间块或种植记录。")
                    }
                    footer(review)
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, theme.pageInset)
                .padding(.vertical, theme.pageSpacing)
                .frame(maxWidth: .infinity)
            }
        }
        .fileExporter(isPresented: $showExport, document: exportDocument, contentType: .commaSeparatedText,
                      defaultFilename: exportDocument?.filename) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
            exportDocument = nil
        }
        .alert("无法导出 CSV", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .confirmationDialog("清空所有日期的番茄统计？时间块和种植记录会保留。",
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空番茄统计", role: .destructive) {
                histogram.clear()
                PomodoroEngine.shared.loadTodayCount()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func report(today: Date, calendar: Calendar) -> FocusReview {
        let end = historyPage?.endDate(range: range, calendar: calendar) ?? today
        return FocusReview(range: range, now: end, histogram: histogram.histogram,
                           dailyBlocks: blockManager.dailyBlocksHistory, blockHistory: blockManager.blockHistory,
                           plants: plants.days, calendar: calendar)
    }

    private func selectedDay(in review: FocusReview) -> FocusReviewDay? {
        if let selectedKey, let day = review.days.first(where: { $0.id == selectedKey }) { return day }
        return review.days.last(where: \.hasRecords) ?? review.days.last
    }

    private func showPreviousPeriod(today: Date) {
        let page = historyPage ?? FocusReviewHistoryPage(anchor: today, offset: 0)
        historyPage = FocusReviewHistoryPage(anchor: page.anchor, offset: page.offset - 1)
        selectedKey = nil
    }

    private func showNextPeriod(today: Date, calendar: Calendar) {
        historyPage = historyPage?.next(today: today, range: range, calendar: calendar)
        selectedKey = nil
    }

    private func returnToToday() {
        historyPage = nil
        selectedKey = nil
    }

    private func periodSummary(_ review: FocusReview, today: Date, calendar: Calendar) -> some View {
        let earliest = FocusReview.earliestDate(histogram: histogram.histogram, dailyBlocks: blockManager.dailyBlocksHistory,
                                               blockHistory: blockManager.blockHistory, plants: plants.days, calendar: calendar)
        let canPageBack = review.days.first.flatMap { first in earliest.map { $0 < first.date } } ?? false

        return VStack(alignment: .leading, spacing: 12) {
            Picker("日期范围", selection: $range) {
                ForEach(FocusReviewRange.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("focus-review-range")
            .onChange(of: range) { _ in returnToToday() }

            HStack(spacing: 8) {
                Button { showPreviousPeriod(today: today) } label: { Image(systemName: "chevron.left") }
                    .help("上一个日期区间")
                    .accessibilityLabel("上一个日期区间")
                    .accessibilityIdentifier("focus-review-previous")
                    .disabled(!canPageBack)
                Text("\(review.startKey) 至 \(review.endKey)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("focus-review-dates")
                Button { showNextPeriod(today: today, calendar: calendar) } label: { Image(systemName: "chevron.right") }
                    .help("下一个日期区间")
                    .accessibilityLabel("下一个日期区间")
                    .accessibilityIdentifier("focus-review-next")
                    .disabled(historyPage == nil)
                Spacer(minLength: 0)
                if historyPage != nil {
                    Button("回到今天", action: returnToToday)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Rectangle().fill(theme.line).frame(height: 1).accessibilityHidden(true)
            HStack(spacing: 10) {
                metric(duration(review.totals.minutes), caption: "专注时长")
                metric("\(review.totals.pomodoros)", caption: "完成番茄")
                metric("\(review.totals.activeDays) 天", caption: "专注天数")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(theme, padding: theme.cardPadding)
    }

    private func trend(_ review: FocusReview, selected: FocusReviewDay, calendar: Calendar) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("专注趋势")
                Spacer()
                Text("按完成的专注分钟计").font(.caption).foregroundStyle(theme.muted)
            }
            if review.days.count <= 7 {
                bars(review.days, selected: selected)
            } else {
                heatmap(review.days, selected: selected, calendar: calendar)
            }
            Text("点选日期查看当日明细")
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(theme, padding: theme.cardPadding)
    }

    private func bars(_ days: [FocusReviewDay], selected: FocusReviewDay) -> some View {
        let peak = max(1, days.map(\.minutes).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { day in
                let active = day.id == selected.id
                dayButton(day, selected: active) {
                    VStack(spacing: 5) {
                        Text("\(day.minutes)")
                            .font(.system(size: 10, weight: active ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(active ? theme.accent : theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.minutes > 0 ? theme.accent.opacity(active ? 1 : 0.60) : theme.line)
                            .frame(width: 15, height: max(3, 54 * CGFloat(day.minutes) / CGFloat(peak)))
                        Text(String(day.id.suffix(5)).replacingOccurrences(of: "-", with: "/"))
                            .font(.system(size: 10, weight: active ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(active ? theme.accent : theme.ink)
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, minHeight: 95, alignment: .bottom)
                    .background(RoundedRectangle(cornerRadius: 6).fill(active ? theme.accentSoft : .clear))
                }
            }
        }
    }

    private func heatmap(_ days: [FocusReviewDay], selected: FocusReviewDay, calendar: Calendar) -> some View {
        let firstWeekday = calendar.firstWeekday
        let startWeekday = days.first.map { calendar.component(.weekday, from: $0.date) } ?? firstWeekday
        let offset = (startWeekday - firstWeekday + 7) % 7
        let columns = (offset + days.count + 6) / 7
        let peak = max(1, days.map(\.minutes).max() ?? 0)
        let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

        return VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: 3) {
                    Text(weekdayNames[(firstWeekday - 1 + row) % 7])
                        .font(.system(size: 10))
                        .foregroundStyle(theme.muted)
                        .frame(width: 14, alignment: .leading)
                        .accessibilityHidden(true)
                    ForEach(0..<columns, id: \.self) { column in
                        let index = column * 7 + row - offset
                        if days.indices.contains(index) {
                            let day = days[index]
                            let active = day.id == selected.id
                            dayButton(day, selected: active) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColor(minutes: day.minutes, peak: peak))
                                    .overlay(RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(active ? theme.ink : .clear, lineWidth: 2))
                                    .frame(height: 17)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            Color.clear.frame(height: 17).accessibilityHidden(true)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("从左到右按周排列")
                Spacer()
                Text("0")
                ForEach([0, 1, 2, 3], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(minutes: level, peak: 3))
                        .frame(width: 9, height: 9)
                }
                Text("较多")
            }
            .font(.caption)
            .foregroundStyle(theme.muted)
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("从左到右按周排列，颜色强度表示专注分钟数")
        }
    }

    private func heatColor(minutes: Int, peak: Int) -> Color {
        guard minutes > 0 else { return theme.subtle }
        return theme.accent.opacity(0.25 + 0.75 * Double(minutes) / Double(peak))
    }

    private func dayButton<Label: View>(_ day: FocusReviewDay, selected: Bool, @ViewBuilder label: () -> Label) -> some View {
        let hint = "\(day.id)，专注 \(day.minutes) 分钟，完成 \(day.pomodoros) 个番茄"
        return Button { selectedKey = day.id } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("focus-review-day-\(day.id)")
    }

    private func dayDetail(_ day: FocusReviewDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("当日明细")
                Spacer()
                Text(day.id)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.accent)
                    .accessibilityIdentifier("focus-review-selected-date")
            }
            if day.hasRecords {
                HStack(spacing: 10) {
                    metric(duration(day.minutes), caption: "专注时长")
                    metric("\(day.pomodoros)", caption: "完成番茄")
                    metric("\(day.completedBlocks)", caption: "达标时间块")
                }
                blockDetails(day.blocks)
                plantDetails(day)
            } else {
                Text("当天没有专注、时间块或种植记录。")
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(theme, padding: theme.cardPadding)
    }

    private func blockDetails(_ blocks: [FocusReviewBlock]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("时间块")
            if blocks.isEmpty {
                Text("当天没有时间块记录").font(.caption).foregroundStyle(theme.muted)
            }
            ForEach(blocks) { block in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("B\(block.id + 1)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.ink)
                    if let goal = block.goal {
                        Text(goal).font(.caption).foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                    Text("\(block.completedPomodoros) 个番茄")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.ink)
                        .fixedSize()
                    if block.isCompleted {
                        Label("曾达标", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                            .fixedSize()
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 5).fill(theme.subtle))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func plantDetails(_ day: FocusReviewDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("种植")
            if day.shrubs > 0 || day.trees > 0 || day.wilted > 0 {
                HStack(spacing: 10) {
                    metric("\(day.shrubs)", caption: "灌木")
                    metric("\(day.trees)", caption: "树")
                    metric("\(day.wilted)", caption: "枯萎")
                }
            } else {
                Text("当天没有种植记录").font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    private func footer(_ review: FocusReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    exportDocument = FocusReviewCSV(text: review.csv, filename: "专注复盘-\(review.startKey)-\(review.endKey).csv")
                    showExport = true
                } label: {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(review.days.isEmpty)
                .accessibilityIdentifier("focus-review-export")
                Spacer(minLength: 0)
                Button("清空番茄统计") { showClearConfirm = true }
                    .disabled(histogram.histogram.isEmpty)
                    .accessibilityIdentifier("focus-review-clear")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text("全部历史 · \(histogram.totalPomodoros) 个番茄 · \(histogram.totalHours.formatted(.number.precision(.fractionLength(1)))) 小时")
                .font(.caption)
                .foregroundStyle(theme.muted)
            Text("记录日均 \(histogram.avgPomodoros.formatted(.number.precision(.fractionLength(1)))) 个番茄")
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) 分钟" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60) 小时" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分"
    }
}

private struct FocusReviewHistoryPage {
    let anchor: Date
    let offset: Int

    func endDate(range: FocusReviewRange, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: offset * range.rawValue, to: anchor).map { calendar.startOfDay(for: $0) }
    }

    func next(today: Date, range: FocusReviewRange, calendar: Calendar) -> Self? {
        // Keep paging from the fixed anchor until the rolling window is next or overlaps it.
        let next = Self(anchor: anchor, offset: offset + 1)
        guard let end = next.endDate(range: range, calendar: calendar), end < today else { return nil }
        return next
    }
}

private struct FocusReviewCSV: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String
    let filename: String

    init(text: String, filename: String) {
        self.text = text
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.init(text: text, filename: configuration.file.preferredFilename ?? "专注复盘.csv")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
