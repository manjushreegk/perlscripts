#!/usr/bin/perl
#module used

use strict;
use warnings;
use Expect;
use XML::Simple;
use Data::Dumper;
use threads;
use Net::SSH::Perl;
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
my $num_of_threads = 1;

print"Creating $ARGV[3] VirtualInterfaces \n";
for (my $i=1; $i <= $ARGV[3]; $i++){
    system("ip link add tap$i type veth peer name ovs-tap$i" );
    }
mkdir $existingdir unless -d $existingdir; # Check if dir exists. If not create it.
my  $xml = new XML::Simple (KeyAttr=>[],forcearray=> qr/(interfaces|neighbor)$/);
# read XML file
my $data = $xml->XMLin("med.xml");

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
my $output1 = "./med1.pl ovs-bgp 2 bgpd 1";
my $host1 = "192.168.44.197";
my $user1 = "isoke";
my $pass1 = "test123";
my $ssh1 = Net::SSH::Perl->new ($host1);
$ssh1->login( $user1, $pass1);
my($stdout1, $stderr1, $exit1) = $ssh1->cmd( $output1);

print "Waiting for the Dut to learn all the routes \n";
sleep(40);
print "Avaliable Paths to the Destination with their Metrics  \n";
result();
foreach my $a (@{$data->{router}}){
     if ($a->{flap}->{name} eq 'enabled'){
          print "Flapping the interfce $a->{flap}->{interface1} ,$a->{flap}->{interface2} in router $a->{name} \n";
          system ("ip netns exec $a->{ns} ifconfig $a->{flap}->{interface1} down ");
          system ("ip netns exec $a->{ns} ifconfig $a->{flap}->{interface2} down ");
          sleep $a->{flap}->{down};
          print "Route Path After Withdrawing The Route With Metric  $a->{med}->{metric} \n";
          result();
}
}
sub result{
open (my $file, '>', 'output.txt') or die "Could not open file: $!";
my $output = "sudo vtysh -c 'sh ip bgp  192.168.44.146'";
my $host = "192.168.44.190";
my $user = "isoke";
my $pass = "test123";
my $ssh = Net::SSH::Perl->new ($host);
$ssh->login( $user, $pass );
my($stdout, $stderr, $exit) = $ssh->cmd( $output);
print  $file $stdout;
close $file ;
stats();
}
sub stats{
my $file_name = 'output.txt';
open(FILE, $file_name) or die "Can't open $file_name: $!";

while (<FILE>) {
next if($_=~/Advertised / );
next if($_=~/BGP /); 
next if($_=~/Last / );
      print $_;

}

}
#Delete all the configuration and clearing all the process 
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
    system("ip link del tap$i type veth peer name ovs-tap$i" );
    }
# BGP configuration sub routine 

sub bgpd_conf{
        
    my $timeout =0.01;
    my $expect_log = "/tmp/output.tmp";
    foreach my $a (@{$data->{router}}) {
         if($a->{ns} eq $_[0]){
         print "***Configuring  Router$a->{name}***\n";
         print "Interface \n";
         {
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
               print "        BGP timers enabled \n";
               print"           Keeplive     $a->{timers}->{keepalive} \n";
               print"           Holddowntime $a->{timers}->{holddowntime}\n";
               if($a->{dampeningparameter}->{name} eq "enabled"){
               print "        BGP Dampening enabled \n";
               print"           Halflife     $a->{dampeningparameter}->{halflife} \n";
               print"           Reuselimit   $a->{dampeningparameter}->{reuselimit} \n";
               print"           Supresslimit $a->{dampeningparameter}->{suppresslimit}\n"; 
               print"           MaximumSuppresslimit $a->{dampeningparameter}->{maximumsuppresslimit}\n";
               }
               if($a->{med}->{name} eq "enabled"){
                       print "        Multi-EXit-Discriminator enabled \n";
                       print "           Metric $a->{med}->{metric} \n";
                   }
                       
              
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
    print"**************************************************************************************\n";
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
    foreach my  $e (@{$data->{router}})
         {
         if($e->{ns} eq $_[0]){
              $exp->expect($timeout, "bgpd(config)#");
              $exp->send( "router bgp $e->{as} \n");
              $exp->expect($timeout, "bgpd(config)#");
              $exp->send("bgp router-id $e->{routerid}\n");
	      $exp->expect($timeout, "bgpd(config)#");
              $exp->send("redistribute connected\n");
              $exp->expect($timeout, "bgpd(config)#");
              $exp->send("timers bgp $e->{timers}->{keepalive} $e->{timers}->{holddowntime} \n");
              foreach my $h (@{$data->{router}})
              {
                   if($h->{ns} eq $_[0]){
                        foreach my $j (@{$h->{neighbor}}){
                             $exp->expect($timeout, "bgpd(config)#");
                             $exp->send("neighbor $j->{ip} remote-as $j->{asno} \n");
                   }
              }
         }
		
              if ($e->{med}->{name} eq 'enabled'){
              $exp->expect($timeout, "bgpd(config)#");
              $exp->send("neighbor $e->{med}->{originatorip} route-map med$_[0] out \n");
		      $exp->expect($timeout, "bgpd(config)#");
		      $exp->send("end \n");
		      $exp->expect($timeout,"bgpd#");
                      $exp->send("configure terminal \n");
                      $exp->expect($timeout,"bgpd(config)#");
		      $exp->send("route-map med$_[0] permit 10 \n");
		      $exp->expect($timeout,"bgpd(config)#");
		      $exp->send("set metric $e->{med}->{metric} \n");
                    #  $exp->expect($timeout, "bgpd(config)#");
                    #  $exp->send("quit\n");
         }
    
        #   else {
            $exp->expect($timeout, "bgpd(config)#");
            $exp->send("quit\n");
            close(EXPECT);
#}
}
}
}

