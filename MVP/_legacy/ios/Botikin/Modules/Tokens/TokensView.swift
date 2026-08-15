import SwiftUI
import Charts
import BotikinKit

struct TokensView: View {
    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = TokensViewModel()
    @State private var mostrandoPlanes = false

    private var accountant: TokenAccountant? { sesion.accountant }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                tarjetaSaldo
                tarjetaCostos
                tarjetaUso
                PrimaryButton(titulo: accountant?.subscription.plan == .pro
                    ? "Ya tienes el plan Pro" : "Mejorar mi plan",
                    deshabilitado: accountant?.subscription.plan == .pro) {
                    mostrandoPlanes = true
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Mis Tokens")
        .refreshable {
            await sesion.refrescarSuscripcion()
            await modelo.cargarUso(token: sesion.accessToken)
        }
        .task {
            await sesion.refrescarSuscripcion()
            await modelo.cargarUso(token: sesion.accessToken)
        }
        .sheet(isPresented: $mostrandoPlanes) {
            NavigationStack { SuscripcionView() }
        }
    }

    // MARK: Saldo y plan

    private var tarjetaSaldo: some View {
        VStack(spacing: 12) {
            HStack {
                StatusBadge(texto: accountant?.subscription.plan.nombre ?? "—",
                            color: .botikinAzul)
                Spacer()
            }

            if let acc = accountant {
                Text(acc.esIlimitado ? "∞" : Formato.miles(acc.saldo))
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Color.botikinVerde)
                Text("tokens disponibles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !acc.esIlimitado {
                    VStack(spacing: 6) {
                        HStack {
                            Label("Tokens disponibles", systemImage: "bolt.circle")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Formato.miles(acc.saldo)) restantes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.botikinVerde)
                        }
                        ProgressView(value: 1 - acc.fraccionConsumida)
                            .tint(Color.botikinVerde)
                        HStack {
                            Text("\(Formato.miles(acc.subscription.tokensUsados)) usados")
                            Spacer()
                            Text("de \(Formato.miles(acc.subscription.tokensTotal))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }

                Text("Renueva en \(acc.diasParaRenovacion()) días")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().padding(.vertical, 30)
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.systemGray5), lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: Costo por acción

    private var tarjetaCostos: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Costo por acción")
                .font(.headline)
                .padding(.bottom, 10)
            ForEach(TokenAction.allCases, id: \.self) { accion in
                HStack {
                    Image(systemName: iconoAccion(accion))
                        .frame(width: 26)
                    Text(accion.nombre)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                        Text("~\(Formato.miles(accion.costo))")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.botikinNaranjo)
                    Image(systemName: (accountant?.puedeEjecutar(accion) ?? false)
                        ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle((accountant?.puedeEjecutar(accion) ?? false)
                            ? Color.botikinVerde : Color.botikinRojo)
                }
                .font(.subheadline)
                .padding(.vertical, 10)
                if accion != TokenAction.allCases.last { Divider() }
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.systemGray5), lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: Gráfico de uso 7 días

    private var tarjetaUso: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uso últimos 7 días")
                .font(.headline)
            if modelo.cargandoUso {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                Chart(modelo.usoUltimos7Dias) { uso in
                    BarMark(
                        x: .value("Día", uso.dia, unit: .day),
                        y: .value("Tokens", uso.tokens))
                        .foregroundStyle(Color.botikinNaranjo)
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if uso.tokens > 0 {
                                Text(compacto(uso.tokens))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow),
                                       centered: true)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 160)
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.systemGray5), lineWidth: 1))
        .padding(.horizontal)
    }

    private func iconoAccion(_ accion: TokenAction) -> String {
        switch accion {
        case .prescriptionAnalysis: "doc.viewfinder"
        case .cabinetAnalysis: "pills"
        case .whatsappMessage: "bubble.left"
        case .assistantChat: "brain.head.profile"
        }
    }

    private func compacto(_ n: Int) -> String {
        n >= 1_000 ? "\(n / 1_000)k" : "\(n)"
    }
}
