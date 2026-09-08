import AppIntents
import WidgetKit

struct StoreEntity: AppEntity, Identifiable, Hashable {
    var id: String
    var name: String

    static let none = StoreEntity(id: "__none__", name: "空")
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "洗衣房" }
    static var defaultQuery: StoreEntityQuery { StoreEntityQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct StoreEntityQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [StoreEntity] {
        [StoreEntity.none] + (AppGroup.loadSelection()?.stores ?? []).map { StoreEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [StoreEntity.ID]) async throws -> [StoreEntity] {
        let byID = Dictionary(uniqueKeysWithValues: try await allEntities().map { ($0.id, $0) })
        return identifiers.map { byID[$0] ?? StoreEntity.none }
    }

    func defaultResult() async -> StoreEntity? {
        StoreEntity.none
    }
}

struct SelectStoresIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "选择洗衣房" }
    static var description: IntentDescription {
        IntentDescription("从 App 已选洗衣房中挑选小组件显示的店，最多 3 家")
    }

    @Parameter(title: "第一家")
    var first: StoreEntity?

    @Parameter(title: "第二家")
    var second: StoreEntity?

    @Parameter(title: "第三家")
    var third: StoreEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("显示 \(\.$first)、\(\.$second)、\(\.$third)")
    }

    init() {
        first = StoreEntity.none
        second = StoreEntity.none
        third = StoreEntity.none
    }

    init(first: StoreEntity?, second: StoreEntity?, third: StoreEntity?) {
        self.first = first
        self.second = second
        self.third = third
    }

    var chosenStores: [StoreEntity] {
        var seen = Set<String>()
        return [first, second, third]
            .compactMap { $0 }
            .filter { $0.id != StoreEntity.none.id }
            .filter { seen.insert($0.id).inserted }
    }
}
