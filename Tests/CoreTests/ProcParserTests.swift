import Testing
@testable import Core

@Suite struct ProcParserTests {
    @Test func keepsOnlyListeningRows() {
        let tcp = """
          sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
           0: 0100007F:20E1 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 41234 1 0 100 0 0 10 0
           1: 0100007F:20E1 0100007F:C350 01 00000000:00000000 00:00000000 00000000  1000        0 41299 1 0 20 4 30 10 -1
           2: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 999 1 0 100 0 0 10 0
        """
        #expect(ProcParser.listening(tcp) == [
            ProcNetSocket(address: "127.0.0.1", port: 8417, uid: 1000, inode: 41234),
            ProcNetSocket(address: "0.0.0.0", port: 8080, uid: 0, inode: 999),
        ])
    }

    @Test func ipv6Addresses() {
        #expect(ProcParser.address(hex: "00000000000000000000000000000000") == "::")
        #expect(ProcParser.address(hex: "00000000000000000000000001000000") == "::1")
        #expect(ProcParser.address(hex: "0000000000000000FFFF00000100007F") == "::ffff:7f00:1")
        #expect(ProcParser.address(hex: "B80D0120000000000000000001000000") == "2001:db8::1")
        #expect(ProcParser.address(hex: "zz") == nil)
    }

    @Test func socketLinksAndStatus() {
        #expect(ProcParser.socketInode(link: "socket:[41234]") == 41234)
        #expect(ProcParser.socketInode(link: "pipe:[41234]") == nil)
        #expect(ProcParser.socketInode(link: "/dev/null") == nil)
        #expect(ProcParser.uid(status: "Name:\tnode\nUid:\t1000\t1000\t1000\t1000\nGid:\t1000\n") == 1000)
        #expect(ProcParser.uid(status: "Name:\tx\n") == nil)
    }
}
