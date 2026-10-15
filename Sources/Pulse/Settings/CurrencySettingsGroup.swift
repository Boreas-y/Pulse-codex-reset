// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Settings → General → Currency: the currency estimates are shown in, and,
/// for any but the dollar, the rate they are converted at.
///
/// **Estimates only**, and the subtitle says so: a balance or a charge a
/// service reports is shown in the currency it gave (`DisplayCurrency`).
///
/// **The source is credited here**, as its terms ask of a page that uses its
/// rates: "Rates By Exchange Rate API", linked (`ExchangeRates.attribution`).
/// Written as the terms give it, in every language — it is a credit, not copy.
struct CurrencySettingsGroup: View {
    let settings: AppSettings

    @State private var rateText = ""
    @FocusState private var rateFocused: Bool

    private var currency: DisplayCurrency { settings.displayCurrency }

    var body: some View {
        SettingsGroup(String.localized("Currency")) {
            SettingsRow(
                String.localized("Show estimates in"),
                subtitle: String.localized("Money worked out from API prices: Token spend, estimated value, usage history and the recap. Balances and charges a service reports stay in the currency it gives.")
            ) {
                Picker("", selection: Binding(
                    get: { settings.displayCurrency },
                    set: { settings.displayCurrency = $0 }
                )) {
                    ForEach(DisplayCurrency.allCases) { currency in
                        Text(currency.title).tag(currency)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
            }

            if currency != .usd {
                SettingsRowDivider()

                SettingsRow(String.localized("Exchange rate"), subtitle: rateSubtitle) {
                    HStack(spacing: 6) {
                        Text(verbatim: "1 USD =")
                            .foregroundStyle(.secondary)
                        TextField("", text: $rateText, prompt: fetchedRate.map { Text(verbatim: Self.text($0)) })
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($rateFocused)
                            .onSubmit(commitRate)
                        Text(verbatim: currency.code)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsRowDivider()

                SettingsRow(String.localized("Rate source")) {
                    Link(destination: ExchangeRates.attribution) {
                        Text(verbatim: "Rates By Exchange Rate API")
                    }
                }
            }
        }
        .onAppear { rateText = Self.text(settings.manualExchangeRates[currency.code]) }
        .onChange(of: settings.displayCurrency) {
            rateText = Self.text(settings.manualExchangeRates[currency.code])
        }
        .onChange(of: rateFocused) {
            if !rateFocused { commitRate() }
        }
    }

    private var fetchedRate: Double? { settings.exchangeRates?.rates[currency.code] }

    private var rateSubtitle: String {
        if settings.manualExchangeRates[currency.code] != nil {
            return .localized("Your rate is used. Clear the field to use the day's rate.")
        }
        if fetchedRate != nil, let updated = settings.exchangeRates?.updatedAt {
            let day = updated.formatted(.dateTime.year().month(.abbreviated).day().locale(LocalizationSource.locale))
            return .localized("The day's rate, updated \(day). Type a rate to use your own.")
        }
        return .localized("No rate yet, so estimates stay in US dollars. Type a rate, or wait for the day's.")
    }

    /// Blank goes back to the fetched rate; anything that is not a positive
    /// number is refused and the field shows what is kept.
    private func commitRate() {
        settings.setManualExchangeRate(Self.rate(rateText), for: currency)
        rateText = Self.text(settings.manualExchangeRates[currency.code])
    }

    /// A rate typed into the field, read the reader's way (a comma decimal
    /// separator included). Nil for blank or anything that is not a positive,
    /// finite number — `Double(_:)` alone would take "inf".
    nonisolated static func rate(_ typed: String, locale: Locale = LocalizationSource.locale) -> Double? {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
            .filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let value = formatter.number(from: trimmed)?.doubleValue
            ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// A rate as the field shows it: up to four places, no grouping.
    nonisolated static func text(_ rate: Double?, locale: Locale = LocalizationSource.locale) -> String {
        guard let rate else { return "" }
        return rate.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(locale))
    }
}
