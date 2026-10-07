import SwiftUI
import Playgrounds

struct ContentView: View {
    
    @State var path: NavigationPath = .init()
    
    var body: some View {
        NavigationStack(path: $path) {
            Access(path: $path)
                .navigationDestination(for: Router.self) { value in
                    switch value {
                    case .login:
                        Login(path: $path)
                    case .verifyCode:
                        VerifyCode(path: $path)
                    case .location:
                        Location(path: $path)
                    case .house:
                        House(path: $path)
                    case .wait:
                        WaitScreen(path: $path)
                    }
                }
        }
    }
}

#Preview {
    ContentView()
}
