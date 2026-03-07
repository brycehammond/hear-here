import SwiftUI

/// Main audio editing screen.
///
/// Layout from top to bottom:
/// - Navigation bar with Back, title, Skip, and Done buttons
/// - Time ruler synced with waveform scroll
/// - Scrollable/zoomable waveform editor
/// - Current time and duration labels
/// - Transport controls (rewind, play/pause, forward)
/// - Edit toolbar at the bottom
struct AudioEditingView: View {
    @Bindable var viewModel: AudioEditingViewModel
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    @State private var zoomLevel: CGFloat = 1.0
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Time ruler
            TimeRulerView(
                duration: viewModel.duration,
                zoomLevel: zoomLevel,
                scrollOffset: scrollOffset
            )
            .padding(.horizontal, Theme.spacingMD)

            // Waveform editor
            WaveformEditorView(
                waveformData: viewModel.waveformData,
                duration: viewModel.duration,
                currentTime: $viewModel.currentTime,
                selectionRange: $viewModel.selectionRange,
                zoomLevel: $zoomLevel,
                scrollOffset: $scrollOffset,
                onSeek: { time in viewModel.seek(to: time) }
            )
            .padding(.horizontal, Theme.spacingMD)
            .padding(.top, Theme.spacingXS)

            // Time labels
            HStack {
                Text(viewModel.formattedCurrentTime)
                    .font(.caption)
                    .foregroundStyle(Theme.onSurface)
                    .monospacedDigit()
                Spacer()
                Text(viewModel.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(Theme.onSurfaceSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.top, Theme.spacingXS)

            Spacer()

            // Transport controls
            transportControls
                .padding(.bottom, Theme.spacingMD)

            // Edit toolbar
            EditToolbarView(
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                canTrimOrCut: viewModel.canTrimOrCut,
                onUndo: { viewModel.undo() },
                onRedo: { viewModel.redo() },
                onTrim: { viewModel.applyTrim() },
                onCut: { viewModel.applyCut() },
                onFadeIn: { viewModel.applyFadeIn() },
                onFadeOut: { viewModel.applyFadeOut() },
                onNormalize: { viewModel.applyNormalize() }
            )
        }
        .navigationTitle("Edit Audio")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Theme.spacingSM) {
                    Button("Skip") {
                        let url = viewModel.skip()
                        onComplete(url)
                    }
                    .foregroundStyle(Theme.onSurfaceSecondary)

                    Button("Done") {
                        Task {
                            let url = await viewModel.exportEdited()
                            onComplete(url)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.state == .processing)
                }
            }
        }
        .overlay {
            if viewModel.state == .processing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView("Processing...")
                            .padding(Theme.spacingLG)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                    }
            }
        }
        .task {
            await viewModel.loadWaveform()
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: Theme.spacingXL) {
            Button {
                viewModel.skipBackward()
            } label: {
                Image(systemName: "gobackward.5")
                    .font(.title2)
            }
            .accessibilityLabel("Rewind 5 seconds")

            Button {
                if viewModel.state == .previewing {
                    viewModel.pause()
                } else {
                    viewModel.play()
                }
            } label: {
                Image(systemName: viewModel.state == .previewing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
            }
            .accessibilityLabel(viewModel.state == .previewing ? "Pause" : "Play")

            Button {
                viewModel.skipForward()
            } label: {
                Image(systemName: "goforward.5")
                    .font(.title2)
            }
            .accessibilityLabel("Forward 5 seconds")
        }
        .foregroundStyle(Theme.accent)
    }
}
