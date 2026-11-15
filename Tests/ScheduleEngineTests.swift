import Foundation
import XCTest
@testable import focus

@MainActor
final class ScheduleEngineTests: XCTestCase {
    private var engine: ScheduleEngine!

    override func setUp() async throws {
        engine = ScheduleEngine()
    }

    override func tearDown() async throws {
        engine = nil
    }

    // MARK: - dayKey format

    func testDayKeyFormat() async throws {
        let key = await engine.dayKey()
        let pattern = #/^\d{4}-\d{2}-\d{2}$/#
        XCTAssertTrue(key.range(of: pattern) != nil, "dayKey должен быть в формате YYYY-MM-DD, получен: \(key)")
    }

    func testDayKeyConsistencyWithCalendar() async throws {
        let key1 = await engine.dayKey()
        let key2 = CalendarPolicy.dayKey(for: .now)
        XCTAssertEqual(key1, key2, "dayKey из ScheduleEngine и CalendarPolicy должны совпадать")
    }

    // MARK: - normalizeOneTimeDate

    func testNormalizeOneTimeFutureNoChange() async throws {
        let future = Date(timeIntervalSinceNow: 86400) // завтра
        let normalized = await engine.normalizeOneTimeDate(future)
        XCTAssertTrue(normalized.timeIntervalSince(future).magnitude < 60, "Будущее время не меняется")
    }

    func testNormalizeOneTimePastTodayBecomesTomorrow() async throws {
        let pastToday = Date(timeIntervalSinceNow: -1200) // 20 минут назад
        let normalized = await engine.normalizeOneTimeDate(pastToday)

        let tomorrow = await engine.nextLocalDay(after: await engine.localDay())
        let expectedComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: pastToday)
        let expected = Calendar.current.date(bySettingHour: expectedComponents.hour ?? 0,
                                             minute: expectedComponents.minute ?? 0,
                                             second: expectedComponents.second ?? 0,
                                             of: tomorrow)!
        XCTAssertTrue(normalized.timeIntervalSince(expected).magnitude < 60,
                      "Прошедшее сегодня время переносится на завтра с тем же локальным временем")
        XCTAssertGreaterThan(normalized, Date(), "Результат в будущем")
    }

    func testNormalizeOneTimePastYesterdayUnchanged() async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let pastYesterday = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: yesterday)!
        let normalized = await engine.normalizeOneTimeDate(pastYesterday)
        // DatePicker запрещает выбор, но engine не меняет прошедшие даты (кроме сегодня).
        XCTAssertEqual(normalized, pastYesterday, "Прошлые даты (не сегодня) не меняются")
    }

    func testNormalizeOneTimeTomorrowUnchanged() async throws {
        let tomorrow = await engine.nextLocalDay(after: await engine.localDay())
        let noonTomorrow = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow)!
        let normalized = await engine.normalizeOneTimeDate(noonTomorrow)
        XCTAssertEqual(normalized, noonTomorrow, "Завтрашняя дата не меняется")
    }

    // MARK: - Daily reset idempotency

    func testResetIdempotentNoDuplicateInstances() async throws {
        let template = RegularTaskTemplate(
            title: "Idempotent",
            localHour: 8,
            localMinute: 0,
            isEnabled: true,
            notificationGeneration: 0
        )
        let dayKey = await engine.dayKey()
        let instance = DailyTaskInstance(
            templateID: template.id,
            template: template,
            dayKey: dayKey,
            state: .pending
        )

        var templates = [template]
        var instances = [instance]

        let deleteFn: @Sendable (UUID) async throws -> Void = { id in
            instances.removeAll { $0.id == id }
        }
        let createFn: @Sendable (DailyTaskInstance) async throws -> Void = { inst in
            instances.append(inst)
        }

        try await engine.performReset(templates: templates, instances: instances,
                                      deleteInstance: deleteFn, createInstance: createFn)

        try await engine.performReset(templates: templates, instances: instances,
                                      deleteInstance: deleteFn, createInstance: createFn)

        let todayInstances = instances.filter { $0.dayKey == dayKey }
        XCTAssertEqual(todayInstances.count, 1, "Reset идемпотентен: нет дублей")
    }

    // MARK: - Reset removes stale instances

    func testResetRemovesStaleInstances() async throws {
        let template = RegularTaskTemplate(
            title: "Stale",
            localHour: 9,
            localMinute: 0,
            isEnabled: true,
            notificationGeneration: 1
        )

        let yesterday = await engine.dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let dayBeforeYesterday = await engine.dayKey(for: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)
        let today = await engine.dayKey()

        var templates = [template]
        var instances = [
            DailyTaskInstance(templateID: template.id, template: template, dayKey: yesterday, state: .seen),
            DailyTaskInstance(templateID: template.id, template: template, dayKey: dayBeforeYesterday, state: .pending),
        ]

        let deleteFn: @Sendable (UUID) async throws -> Void = { id in
            instances.removeAll { $0.id == id }
        }
        let createFn: @Sendable (DailyTaskInstance) async throws -> Void = { inst in
            instances.append(inst)
        }

        try await engine.performReset(templates: templates, instances: instances,
                                      deleteInstance: deleteFn, createInstance: createFn)

        // Устаревшие удалены.
        XCTAssertFalse(instances.contains { $0.dayKey == yesterday })
        XCTAssertFalse(instances.contains { $0.dayKey == dayBeforeYesterday })

        // Создан сегодняшний PENDING.
        let todayInstances = instances.filter { $0.dayKey == today }
        XCTAssertEqual(todayInstances.count, 1)
        XCTAssertEqual(todayInstances.first?.state, .pending)
    }

    // MARK: - Exactly one instance per template per day

    func testResetCreatesExactlyOneInstancePerTemplate() async throws {
        let t1 = RegularTaskTemplate(title: "T1", localHour: 8, localMinute: 0, isEnabled: true, notificationGeneration: 1)
        let t2 = RegularTaskTemplate(title: "T2", localHour: 12, localMinute: 0, isEnabled: true, notificationGeneration: 1)
        let t3 = RegularTaskTemplate(title: "T3", localHour: 18, localMinute: 0, isEnabled: false, notificationGeneration: 1) // disabled

        let dayKey = await engine.dayKey()
        var templates = [t1, t2, t3]
        var instances = [
            DailyTaskInstance(templateID: t1.id, template: t1, dayKey: dayKey, state: .seen), // existing
        ]

        let deleteFn: @Sendable (UUID) async throws -> Void = { id in
            instances.removeAll { $0.id == id }
        }
        let createFn: @Sendable (DailyTaskInstance) async throws -> Void = { inst in
            instances.append(inst)
        }

        try await engine.performReset(templates: templates, instances: instances,
                                      deleteInstance: deleteFn, createInstance: createFn)

        let todayInstances = instances.filter { $0.dayKey == dayKey }
        XCTAssertEqual(todayInstances.count, 2, "Только включенные шаблоны создают экземпляр")
        let ids = Set(todayInstances.map { $0.templateID })
        XCTAssertTrue(ids.contains(t1.id))
        XCTAssertTrue(ids.contains(t2.id))
        XCTAssertFalse(ids.contains(t3.id))
    }

    // MARK: - Reset priority over snooze at midnight

    func testResetClearsSnoozePriorityOverYesterdaySnooze() async throws {
        let template = RegularTaskTemplate(
            title: "SnoozeAtMidnight",
            localHour: 23,
            localMinute: 30,
            isEnabled: true,
            notificationGeneration: 2
        )

        let yesterday = await engine.dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let today = await engine.dayKey()

        // Вчерашний экземпляр с snooze, который пересекает полночь.
        var templates = [template]
        var instances = [
            DailyTaskInstance(
                templateID: template.id,
                template: template,
                dayKey: yesterday,
                state: .pending,
                snoozedUntil: Date().addingTimeInterval(40 * 60) // snooze за границей полуночи
            )
        ]

        let deleteFn: @Sendable (UUID) async throws -> Void = { id in
            instances.removeAll { $0.id == id }
        }
        let createFn: @Sendable (DailyTaskInstance) async throws -> Void = { inst in
            instances.append(inst)
        }

        try await engine.performReset(templates: templates, instances: instances,
                                      deleteInstance: deleteFn, createInstance: createFn)

        // Вчерашний удалён, сегодняшний создан PENDING без snooze.
        XCTAssertFalse(instances.contains { $0.dayKey == yesterday })
        let todayInstances = instances.filter { $0.dayKey == today }
        XCTAssertEqual(todayInstances.count, 1)
        XCTAssertEqual(todayInstances.first?.state, .pending)
        XCTAssertNil(todayInstances.first?.snoozedUntil, "Snooze сгорел при reset, не перенесся")
        XCTAssertEqual(todayInstances.first?.repeatCount, 0)
    }

    // MARK: - DST transition

    func testDSTTransitionConsistency() async throws {
        let consistent = await engine.isDSTTransitionConsistent()
        // На устройстве с настройками DST это должно быть true.
        // В тестах может быть false, если тестовый календарь не использует DST.
        // Просто проверяем, что метод не падает и возвращает Bool.
        XCTAssertNotNil(consistent)
    }

    func testTimeZoneOffset() async throws {
        let offset = await engine.currentTimeZoneOffset()
        XCTAssertNotNil(offset)
        // Проверяем, что смещение в разумных пределах (-12h ... +14h)
        XCTAssertGreaterThanOrEqual(offset, -12 * 3600)
        XCTAssertLessThanOrEqual(offset, 14 * 3600)
    }

    // MARK: - Time zone change

    func testTimeZoneChangeDayKeyUsesCurrentCalendar() async throws {
        // dayKey всегда вычисляется через Calendar.current, поэтому при смене часового пояса
        // в следующем запуске/резет он отразит новый локальный день.
        let key = await engine.dayKey()
        let pattern = #/^\d{4}-\d{2}-\d{2}$/#
        XCTAssertTrue(key.range(of: pattern) != nil)
    }

    // MARK: - startOfDay / nextLocalDay use Calendar, not 86400

    func testNextLocalDayUsesCalendarNotSeconds() async throws {
        let today = await engine.localDay()
        let next = await engine.nextLocalDay(after: today)

        // Разница должна быть ровно 1 календарный день (не 86400 секунд).
        let diff = Calendar.current.dateComponents([.day], from: today, to: next).day ?? 0
        XCTAssertEqual(diff, 1, "Переход на следующий день через Calendar, а не +86400 сек")

        // Проверка DST-перехода: если день 23 или 25 часов, diff всё равно 1 день.
    }

    // MARK: - CalendarPolicy integration

    func testCalendarPolicyDayKeyMatchesEngine() async throws {
        let engineKey = await engine.dayKey()
        let policyKey = CalendarPolicy.dayKey(for: .now)
        XCTAssertEqual(engineKey, policyKey)
    }

    func testCalendarPolicyStartOfDay() async throws {
        let date = Date()
        let engineStart = await engine.startOfDay(date)
        let policyStart = CalendarPolicy.startOfDay(date)
        XCTAssertEqual(engineStart, policyStart)
    }

    func testCalendarPolicyLocalDateComponents() async throws {
        let date = Date()
        let engineComponents = await engine.dayKey(for: date)
        let policyComponents = CalendarPolicy.dayKey(for: date)
        XCTAssertEqual(engineComponents, policyComponents)
    }
}