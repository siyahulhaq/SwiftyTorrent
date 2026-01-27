//
//  ControlsView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

struct ControlsView: View {
    @ObservedObject var controlsVM: ControlsViewModel
    @State var isTotalTime = false
    let deligate: PlayerControlsProtocol
    let imageSize: CGFloat = 25.0
    let imageSize2: CGFloat = 40.0
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    deligate.onClose()
                }) {
                    Image(systemName: "xmark")
                        .resizable()
                        .frame(width: imageSize, height: imageSize)
                        .foregroundColor(.white)
                }
                Spacer()
                VStack{
                    Text(controlsVM.fileName)
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    
                }
            }
            .padding(.all, 20)
            
            Spacer()
            
            HStack {
                Spacer()
                Button(action: deligate.onBackward) {
                    Image(systemName: "gobackward.10")
                        .resizable()
                        .frame(width: imageSize2, height: imageSize2)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                
                
                Button(action: {
                    self.deligate.onTogglePlayPause()
                }){
                    Image(systemName: controlsVM.isPlaying ? "pause" : "play")
                        .resizable()
                        .frame(width: imageSize2, height: imageSize2)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                Button(action: {
                    deligate.onForward()
                }) {
                    Image(systemName: "goforward.10")
                        .resizable()
                        .frame(width: imageSize2, height: imageSize2)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                Spacer()
            }
            .padding()
            
            Spacer()
            
            HStack {
                Text(controlsVM.currentTime)
                    .foregroundColor(.white)
                Slider(value: Binding(get: {
                    controlsVM.volume
                }, set: { value in
                    deligate.changeVolume(value)
                }))
                .frame(width: 100)
                Spacer()
                if(!controlsVM.audioTracks.isEmpty) {
                    Menu {
                        ForEach(controlsVM.audioTracks, id: \.index) { track in
                            Button(action: {
                                deligate.onAudioTrackSelected(track.index)
                            }) {
                                HStack {
                                    Text(track.name)
                                    if track.index == controlsVM.selectedAudioTrack {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "waveform.circle")
                            .resizable()
                            .frame(width: imageSize, height: imageSize)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                    }
                }
                
                if(!controlsVM.subtitleTracks.isEmpty) {
                    Menu {
                        ForEach(controlsVM.subtitleTracks, id: \.index) { track in
                            Button(action: {
                                deligate.onSubtitleTrackSelected(track.index)
                            }) {
                                HStack {
                                    Text(track.name)
                                    if track.index == controlsVM.selectedSubtitleTrack {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "text.bubble")
                            .resizable()
                            .frame(width: imageSize, height: imageSize)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                    }
                }
                
                
                Text(isTotalTime ? controlsVM.totalTime : controlsVM.remainingTime)
                    .foregroundColor(.white)
                    .onTapGesture {
                        isTotalTime = !isTotalTime
                    }
            }.padding(.horizontal, 20)
            
            Slider(value: Binding(
                get: { Double(controlsVM.position) },
                set: {
                    let pos = Float($0)
                    controlsVM.position = pos;
                    self.deligate.onSliderChange(pos)
                }
            ), in: 0...1)
            .padding()
        }
        .background(Color.black.opacity(0.01))
    }
}
