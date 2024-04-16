/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;
const bit<8> PROTO_FILTER = 146;
const bit<8> PROTO_UDP = 17;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

// TODO: Define the filter and UDP headers here.

header udp_t {
  bit<16>     srcPort;
  bit<16>     dstPort;
  bit<16>     length_;
  bit<16>     checksum;
}

header filter_t {
  bit<8> susp; // 8 bits - set to one if a packet is suspicious and zero otherwise. Originally, this fields is zero for all packets that enter the network.
  bit <8> proto; // 8 bits -  determines what protocol the next header belongs to. All the packets 
                 //           that enter the network will have this fields set to 17, which means the next header will be a UDP header. You can find a sketch of the UDP header here
}

struct metadata {
    /* empty */
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;

    // TODO: instantiate the filter and udp headers here
    udp_t         udp;
    filter_t      filter;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        /* TODO: transition to either parsing the 
                 filter header or accept depending
                 on hdr.ipv4.protocol
        */ 

        transition select(hdr.ipv4.protocol) {
          PROTO_FILTER: parse_filter;
          default: accept;
        }
    }

    /* TODO: add two parser states, one for parsing
             the filter header and one for parsing
             the UDP header
    */

    state parse_filter {
      parse.extract(hdr.filter);

      transition select(hdr.filter.proto) {
        PROTO_UDP: parse_udp;
        // default: accept;
      }
    }

    state parse_udp {
      parse.extract(hdr.udp);
      transition accept;
    
    }
}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    /* TODO: define an action to set the
             susp field in the filter header
    */      

    action set_susp() {
      hdr.filter.susp = 1;
    }
    /* TODO: define a table that matches on
             source IP address and UDP source
             port, and applies the above actions
             as an option
    */

    table filter_exact {
      key = {
        hdr.ipv4.srcAddr: exact;
        hdr.udp.srcPort: exact;
      }
      
      actions = { 
        set_susp;
        drop; // MY TODO: see if this is necessary
      }

      size = 1024; // MY TODO: determine how big the filter table should be in bytes!
      default_action = drop(); // MY TODO: see if this is necessary

    }

    action drop() {
        mark_to_drop(standard_metadata);
    }

    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_exact {
        key = {
            hdr.ipv4.dstAddr: exact;
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = drop();
    }

    apply {
        if (hdr.ipv4.isValid()) {

            /* TODO: Check if the filter and UDP headers
                     have been parsed. If yes, apply
                     the filter table
            */
            ipv4_exact.apply(); // MY TODO: see if I should validate beforehand as well!

            if (hdr.filter.isValid() && hdr.udp.isValid()) {
                filter_exact.apply();
        }

        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
        update_checksum(
        hdr.ipv4.isValid(),
            { hdr.ipv4.version,
              hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        /* TODO: use the emit function to
                 to emit the filter and udp
                 headers as well
        */
        packet.emit(hdr.filter);
        packet.emit(hdr.udp);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
