import ComposableArchitecture
import SwiftUI

@Reducer
struct VoiceMemo {
  @ObservableState
  struct State: Equatable, Identifiable {
    var date: Date
    var duration: TimeInterval
    var mode = Mode.notPlaying
    var title = ""
    var url: URL

    // TODO: Why is this needed?
    init(
      date: Date,
      duration: TimeInterval,
      mode: Mode = .notPlaying,
      title: String = "",
      url: URL
    ) {
      self.date = date
      self.duration = duration
      self.mode = mode
      self.title = title
      self.url = url
    }

    var id: URL { self.url }

    @CasePathable
    @dynamicMemberLookup
    enum Mode: Equatable {
      case notPlaying
      case playing(progress: Double)
    }
  }

  enum Action: BindableAction {
    case audioPlayerClient(Result<Bool, Error>)
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case playButtonTapped
    case timerUpdated(TimeInterval)

    @CasePathable
    enum Delegate {
      case playbackStarted
      case playbackFailed
    }
  }

  @Dependency(\.audioPlayer) var audioPlayer
  @Dependency(\.continuousClock) var clock
  private enum CancelID { case play }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .audioPlayerClient(.failure):
        state.mode = .notPlaying
        return .merge(
          .cancel(id: CancelID.play),
          .send(.delegate(.playbackFailed))
        )

      case .audioPlayerClient:
        state.mode = .notPlaying
        return .cancel(id: CancelID.play)

      case .binding:
        return .none

      case .delegate:
        return .none

      case .playButtonTapped:
        switch state.mode {
        case .notPlaying:
          state.mode = .playing(progress: 0)

          return .run { [url = state.url] send in
            await send(.delegate(.playbackStarted))

            async let playAudio: Void = send(
              .audioPlayerClient(Result { try await self.audioPlayer.play(url) })
            )

            var start: TimeInterval = 0
            for await _ in self.clock.timer(interval: .milliseconds(500)) {
              start += 0.5
              await send(.timerUpdated(start))
            }

            await playAudio
          }
          .cancellable(id: CancelID.play, cancelInFlight: true)

        case .playing:
          state.mode = .notPlaying
          return .cancel(id: CancelID.play)
        }

      case let .timerUpdated(time):
        switch state.mode {
        case .notPlaying:
          break
        case .playing:
          state.mode = .playing(progress: time / state.duration)
        }
        return .none
      }
    }
  }
}

struct VoiceMemoView: View {
  @State var store: StoreOf<VoiceMemo>

  var body: some View {
    let currentTime =
      store.mode.playing.map { $0 * store.duration } ?? store.duration
    HStack {
      TextField(
        "Untitled, \(store.date.formatted(date: .numeric, time: .shortened))",
        text: $store.title
      )

      Spacer()

      dateComponentsFormatter.string(from: currentTime).map {
        Text($0)
          .font(.footnote.monospacedDigit())
          .foregroundColor(Color(.systemGray))
      }

      Button {
        store.send(.playButtonTapped)
      } label: {
        Image(systemName: store.mode.is(\.playing) ? "stop.circle" : "play.circle")
          .font(.system(size: 22))
      }
    }
    .buttonStyle(.borderless)
    .frame(maxHeight: .infinity, alignment: .center)
    .padding(.horizontal)
    .listRowBackground(store.mode.is(\.playing) ? Color(.systemGray6) : .clear)
    .listRowInsets(EdgeInsets())
    .background(
      Color(.systemGray5)
        .frame(maxWidth: store.mode.is(\.playing) ? .infinity : 0)
        .animation(
          store.mode.is(\.playing) ? .linear(duration: store.duration) : nil,
          value: store.mode.is(\.playing)
        ),
      alignment: .leading
    )
  }
}
