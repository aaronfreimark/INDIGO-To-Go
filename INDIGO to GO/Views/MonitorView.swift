//
//  ContentView.swift
//  INDIGO Status
//
//  Created by Aaron Freimark on 9/9/20.
//

import SwiftUI

struct MonitorView: View {
    
    /// The interesting stuff is in this object!
    @EnvironmentObject var client: IndigoClientViewModel
        
    @State var isShowingSpinner = true
    
    /// Keep track of whether a sheet is showing or not.
    @State private var isSettingsSheetShowing: Bool = false
    @State private var isAlertShowing: Bool = false
    @State private var isTimesShowing: Bool = false
    
    var body: some View {
        
        List {
            if !client.isAnythingConnected {
                HStack {
                    Spacer()
                    ProgressView()
                        .font(.largeTitle)
                        .padding(30)
                    Text("No INDIGO agents are connected. Please tap Settings to identify agents on your local network.")
                }
                .font(.footnote)
                
                #if DEBUG
                Text("Connected: \(client.isAnythingConnected ? "Y" : "N")")
                Text("Imager: \(client.isImagerConnected ? "Y" : "N")")
                Text("Guider: \(client.isGuiderConnected ? "Y" : "N")")
                Text("Mount: \(client.isMountConnected ? "Y" : "N")")
                #endif
            }

            // =================================================================== SEQUENCE

            if client.isImagerConnected || client.isMountConnected {
                Section {
                    if client.isImagerConnected  {
                        ImagerProgressView()
                            .environmentObject(client)
                    }
                }


                Section(header: Text("Sequence")) {
                    StatusRowView(sr: client.srSequenceStatus)
                    DisclosureGroup("Timing") {
                        ForEach(client.timeStatusRows) { sr in
                            StatusRowView(sr: sr)
                        }
                    }
                }
            }

//            if client.isImagerConnected {
//                ImagerPreviewView().environmentObject(client)
//            }

            // =================================================================== GUIDER

            if client.isGuiderConnected {
                Section(header: Text("Guider")) {
                    StatusRowView(sr: client.srGuidingStatus)
                    StatusRowView(sr: client.srRAError)
                    StatusRowView(sr: client.srDecError)
                }
            } else {
                EmptyView()
            }

            // =================================================================== HARDWARE

            if client.isMountConnected || client.isImagerConnected {
                Section(header: Text("Hardware")) {
                    StatusRowView(sr: client.srCoolingStatus)
                    StatusRowView(sr: client.srMountStatus)
                }
            }
            
            Section(footer:
                        VStack(alignment: .leading) {
                            ForEach(client.connectedServers(), id: \.self ) { name in
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                    Text(name)
                                }
                            }
                        }) {

//                Button(action: { client.printProperties() } ) { Text("Properties") }

                /// Park & Warm Button
                if client.isMountConnected || client.isImagerConnected {
                    ParkAndWarmButton
                }

                /// Servers Button
//                Button(action: serversButton) {
//                    Text("Servers")
//                }
//                .sheet(isPresented: $isSettingsSheetShowing, content: { SettingsView().environmentObject(client) })
            }
            
        }
        .listStyle(GroupedListStyle())
    }
    
    private var ParkAndWarmButton: some View {
        Button(action: { self.isAlertShowing = true }) {
            Text(client.parkButtonTitle)
        }
        .disabled(!client.isParkButtonEnabled)
        .alert(isPresented: $isAlertShowing, content: {
            Alert(
                title: Text(client.parkButtonTitle),
                message: Text(client.parkButtonDescription),
                primaryButton: .destructive(Text(client.parkButtonOK), action: {
                    isAlertShowing = false
                    client.emergencyStopAll()
                }),
                secondaryButton: .cancel(Text("Cancel"), action: {
                    isAlertShowing = false
                })
            )
        })
    }

    func showSpinner() {
        let duration = 5.0
        
        self.isShowingSpinner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.isShowingSpinner = false
        }
    }
    
    private func serversButton() {
        self.isSettingsSheetShowing = true
    }
    
    
}




struct MonitorView_Previews: PreviewProvider {
    static var previews: some View {
        let client = IndigoClientViewModel(client: MockIndigoClientForPreview(), isPreview: true)
        MonitorView()
            .environmentObject(client)
    }
}
