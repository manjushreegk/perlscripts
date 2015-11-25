#!/usr/bin/perl

#module used
use strict;
use warnings;
use Expect;
use XML::Simple;
use Data::Dumper;
use Net::Ping::External;
my $bridge_name =$ARGV[0];

#my $existingdir = $ARGV[2];
my $existingdir = "/etc/quagga";
my $network3 = 1;
my $network2 = 1;
my $network1 = 10;
my $ip3 = 1;
my $ip4 =0;
my $config = $ARGV[2];
my $bgpd = "bgpd";
my $ospfd = "ospfd";
my $ripd = "ripd";
my $count =0;
my $count1=0;
my $totalroutes=0;

print "Creating Bridge $bridge_name\n";
system ("ovs-vsctl add-br  $bridge_name ");
print"Creating $ARGV[3] VirtualInterfaces \n";
for (my $i=1; $i <= $ARGV[3]; $i++){
    system("ip link add tap$i type veth peer name peertap$i" );
}
mkdir $existingdir unless -d $existingdir; # Check if dir exists. If not create it.
my  $xml = new XML::Simple (KeyAttr=>[],forcearray=> qr/(interfaces|neighbor)$/);
# read XML file
my $data = $xml->XMLin("capacity.xml");
for (my $i=1; $i <= $ARGV[1]; $i++){
     print "\n";        
     print "*******Adding Router$i ************ \n";
     system ("ip netns add NS$i ");
     print "Creating Configuration file for Router$i\n ";
     my  $br_file = "$ARGV[2]_NS$i.conf";
     my  $zr_file = "zebra_NS$i.conf";
     unless(open BR_FILE ,">>", "$existingdir/$ARGV[2]_NS$i.conf" ){
          die "Can't open '$existingdir/$ARGV[2]_Ns$i.conf'\n";
     }
     unless(open ZR_FILE ,">>", "$existingdir/zebra_NS$i.conf" ){
          die "Can't open '$existingdir/zebra_Ns$i.conf'\n";
     }
     print BR_FILE "password zebra\n";
     print BR_FILE "line vty\n";
     close BR_FILE;
     print ZR_FILE "password zebra\n";
     print ZR_FILE "line vty\n";
     close ZR_FILE;
     system("ip netns exec NS$i zebra -f $existingdir/zebra_NS$i.conf -i /var/run/quagga/zebra_NS$i.pid -d");
     system("ip netns exec NS$i $ARGV[2] -f $existingdir/$ARGV[2]_NS$i.conf  -i /var/run/quagga/$ARGV[2]_NS$i.pid -d");
     system("ip  netns exec NS$i ifconfig lo up");
     if($config eq $bgpd){
          bgpd_conf("NS$i","100$i","$network1.$network2.$network3");
     }
     elsif($config eq $ospfd){
          ospfd_conf("NS$i","$network1.$network2.$network3","0.0.0.$i");
     }
     elsif($config eq $ripd){
          ripd_conf("NS$i","$network1.$network2.$network3");
     }
}


#calculate the num of routes dut can hold
my $routes = $count -$count1 ; 
print "DUT can advertise $routes routes \n";
if($routes == $totalroutes){
print "Test Completed Successfully \n";
}

sleep 30;
#Delete all the conifuration 
system ("ovs-vsctl del-br $ARGV[0] ");
system("killall -9 zebra");
system("killall -9 bgpd");
#system("killall -9 ospfd");
system("killall -9 $config");
for(my $i=1 ; $i <=$ARGV[1] ;$i++){
     system("ip netns del NS$i");
     system("rm -rf $existingdir/$ARGV[2]_NS$i.conf");
     system("rm -rf $existingdir/zebra_NS$i.conf");
}    

for (my $i=1; $i <= $ARGV[3]; $i++){
    system("ip link del tap$i type veth peer name peertap$i" );
}
# BGP configuration sub routine 
sub bgpd_conf{
     my $timeout = 0.01;
     my $expect_log = "/tmp/output.tmp";
     foreach my $a (@{$data->{router}}) {
          if($a->{ns} eq $_[0]){
               print "***Configuring  Router$a->{name}***\n";
               print "Interface \n";
               foreach my $b (@{$a->{interfaces}})
               {   
                    print "	InterfaceName : $b->{InterfaceName} \n";
                    print "	IP Address $b->{interfaceip}/$b->{subnet} \n";
                    print "\n";
               }  
               print "Configuring BGP For Router$a->{name} \n";
               print "	Routerid $a->{routerid} \n"; 
               foreach my $k (@{$a->{neighbor}})
               {   
                    print "	neighbor $k->{ip} in AS $k->{asno}\n";
               }
               print"**************************************************************************************\n";
               if($a->{capacity}->{name} eq "enabled"){
                    print "Test Setup \n" ;
                    print "Number of Routes Per Peer $a->{capacity}->{routes} \n";
                    print "Number of Routes Step $a->{capacity}->{delay} \n";
                    print "Delay $a->{capacity}->{sleep} \n";
                    print "Number of Iteration $a->{capacity}->{iteration} \n";
                    print"**************************************************************************************\n";
                    $totalroutes= $a->{capacity}->{routes} + ($a->{capacity}->{delay} *$a->{capacity}->{iteration});
               }  
          } 
     } 
     foreach my $f (@{$data->{router}})
     { 
          if($f->{ns} eq $_[0]){
               foreach my $g (@{$f->{interfaces}}){
                    system ("ip link set $g->{InterfaceName} netns $_[0] \n");
                    system ("ip netns exec $_[0] ip add add $g->{interfaceip}/$g->{subnet} dev $g->{InterfaceName} \n");
                    system ("ip netns exec $_[0] ifconfig $g->{InterfaceName} up \n");
               }
          }  
     } 
     unless(open EXPECT, ">>","$expect_log"){
        die ("Cannot open the expect log file: $expect_log $!\n");
     } 
     my $exp = Expect->spawn("ip netns exec  $_[0]  telnet localhost 2605");
     $exp->log_stdout(0);
     $exp->log_file("$expect_log");
     $exp->expect($timeout, "Password:");
     $exp->send("zebra\n");

     $exp->expect($timeout, "bgpd>");
     $exp->send("enable\n");

     $exp->expect($timeout, "bgpd#");
     $exp->send("show run\n");

     $exp->expect($timeout, "bgpd#");
     $exp->send("configure terminal\n");
     foreach my $e (@{$data->{router}}){
          if($e->{ns} eq $_[0]){
               system ("ip netns exec $_[0] route add default gw $e->{gateway}");
               $exp->expect($timeout, "bgpd(config)#");
               $exp->send( "router bgp $e->{as} \n");
       
               $exp->expect($timeout, "bgpd(config)#");
               $exp->send("bgp router-id $e->{routerid}\n");
               foreach my $h (@{$data->{router}})
               {
                    if($h->{ns} eq $_[0]){
                         foreach my $j (@{$h->{neighbor}}){
                              $exp->expect($timeout, "bgpd(config-router)#");
                              $exp->send("neighbor $j->{ip} remote-as $j->{asno} \n");
                         }
                    }
               }
               if ($e->{capacity}->{name} eq 'enabled'){
                    my $list = $e->{capacity}->{ipaddress};
                    my @network =split(/\./,$list);
                    my $routes = $e->{capacity}->{delay} * $e->{capacity}->{iteration};
                    my $noofroutes = $routes + $e->{capacity}->{routes} ;
                    my $initialroutes=$e->{capacity}->{routes} ;
                    for(my $i=1 ; $i <= $e->{capacity}->{routes}; $i++){
                         if ($network[2]== 255) {
                              $network[2] = 1;
                              $network[1] ++;
                         }
                         if ($network[1] == 255) {
                               $network[1] = 1;
                               $network[0]++;
                         }
                         if ($network[0] == 255) {
                               $network[0] = 1;
                         }
                         system("ip netns exec $_[0] ip add add $network[0].$network[1].$network[2].1/24 dev lo\n");
                         $exp->expect($timeout, "bgpd(config-router)#");
                         $exp->send("network $network[0].$network[1].$network[2].$network[3]/24\n");
                         $network[2]++;
                         }
                         sleep($e->{capacity}->{sleep});
                         my $list1 = $e->{capacity}->{ipaddress};
                         my @pnetwork =split(/\./,$list1);
                         open (my $file, '>', 'output') or die "Could not open file: $!";
                         print "Pinging Initial Routes Advertised .... \n";
                         for(my $t=1 ;$t<= $initialroutes;$t++){ 
                              if ($pnetwork[2]== 255) {
                                   $pnetwork[2] = 1;
                                   $pnetwork[1] ++;
                               }
                               if ($pnetwork[1] == 255) {
                                    $pnetwork[1] = 1;
                                    $pnetwork[0]++;
                                }
                                if ($pnetwork[0] == 255) {
                                     $pnetwork[0] = 1;
                                }
                           my $stdout = `ip netns exec NS1 ping -c 1  $pnetwork[0].$pnetwork[1].$pnetwork[2].1 | grep 'packet loss' `;
                           unless ($stdout =~ /(\d+)% packet loss/ ) {
                               die ( "Bad Response:\n$stdout\n" );
                           }
                           my $loss = $1;
                           if($loss == 100 ){ 
                               print $file  " ip $pnetwork[0].$pnetwork[1].$pnetwork[2].1 Unreachable $loss Packet loss\n";
                               $count1++;
                               print $file $stdout ;
                           }
                           $pnetwork[2]++;
                           $count++;
                           }
                           for(my $r=1 ;$r <= $e->{capacity}->{iteration} ;$r++){
                                for(my $i=1 ; $i <= $e->{capacity}->{delay}; $i++){
                                     if ($network[2]== 255) {
                                          $network[2] = 1;
                                          $network[1] ++;
                                     }
                                     if ($network[1] == 255) {
                                          $network[1] = 1;
                                          $network[0]++;
                                     }  
                                     if ($network[0] == 255) {
                                          $network[0] = 1;
                                     } 
                                     system("ip netns exec $_[0] ip add add $network[0].$network[1].$network[2].1/24 dev lo\n");
                                     $exp->expect($timeout, "bgpd(config-router)#");
                                     $exp->send("network $network[0].$network[1].$network[2].$network[3]/24\n");
                                     $network[2]++;
                                }
                          sleep($e->{capacity}->{sleep}) ;
                          print "Pinging the next $e->{capacity}->{delay}  routes advertised (Iteration $r) \n";
                          for(my $u=1 ;$u<= $e->{capacity}->{delay} ;$u++){
                               if ($pnetwork[2]== 255) {
                                     $pnetwork[2] = 1;
                                     $pnetwork[1] ++;
                                }
                                if ($pnetwork[1] == 255) {
                                     $pnetwork[1] = 1;
                                     $pnetwork[0]++;
                                }
                                if ($pnetwork[0] == 255) {
                                     $pnetwork[0] = 1;
                                }
                                my $stdout1 = `ip netns exec NS1 ping $pnetwork[0].$pnetwork[1].$pnetwork[2].1 -c 1  | grep 'packet loss'`;
                                  unless ($stdout1 =~ /(\d+)% packet loss/ ) {
                                  die ( "Bad Response:\n$stdout1\n" );
                                }
                                my $loss1 = $1;
                                if($loss1 == 100){
                                    print $file  " ip $pnetwork[0].$pnetwork[1].$pnetwork[2].1 Unreachable $loss1 Packet loss\n";
                                    print $file $stdout1;
                                    $count1++;  
                                } 
                                $pnetwork[2]++;
                                $count++ ;
                         }
                    }
                }
 
                $exp->expect($timeout, "bgpd(config)#");
                $exp->send("redistribute connected\n");
                $exp->expect($timeout, "bgpd(config)#");
                $exp->send("redistribute kernel\n");
                $exp->expect($timeout, "bgpd(config)#");
                $exp->send("quit\n");
               close(EXPECT);  
          }
     }
}

