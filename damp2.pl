#!/usr/bin/perl

#module used
use strict;
use warnings;
use Expect;
use XML::Simple;
use Data::Dumper;
use Net::SSH::Perl;
use threads;
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
print "Creating Bridge $bridge_name\n";
system ("ovs-vsctl add-br  $bridge_name ");
print"Creating $ARGV[3] VirtualInterface\n";
for (my $i=1; $i <= $ARGV[3]; $i++){
    system("ip link add tap$i type veth peer name peertap$i" );
}
mkdir $existingdir unless -d $existingdir; # Check if dir exists. If not create it.
my  $xml = new XML::Simple (KeyAttr=>[],forcearray=> qr/(interfaces|neighbor)$/);
# read XML file
my $data = $xml->XMLin("bgpdamp1.xml");

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
sleep(30);
print "Waiting for the dut to advertise the route \n";
open (my $file, '>', 'output.txt') or die "Could not open file: $!";
my @sec= localtime ;
print "Flapping the interface for 5 min .......... \n";
while($sec[6] <= 100 ){
     foreach my $a (@{$data->{router}}){
          if ($a->{flap}->{name} eq 'enabled'){
        # my @sec= localtime ;
        #      while($sec[6] <= 80 ){
               #print "$sec[6] \n";
               system ("ip netns exec $a->{ns} ifconfig $a->{flap}->{interface} down ");
               sleep $a->{flap}->{down};
               my $duration = $sec[6] +sleep $a->{flap}->{down} ;
               system ("ip netns exec $a->{ns} ifconfig  $a->{flap}->{interface} up ");
               stats() ;
               sleep $a->{flap}->{up};
               my $sec1 = $duration+sleep $a->{flap}->{up};
               $sec[6] =$sec1 ;
              }
         }

    }

sub stats {
my $host = "192.168.44.190";
my $user = "isoke";
my $password = "test123";

#-- set up a new connection
my $ssh = Net::SSH::Perl->new($host,protocol => '1,2');
#-- authenticate
$ssh->login($user, $password);
#-- execute the command
#open (my $file, '>', 'output.txt') or die "Could not open file: $!";
my($stdout, $stderr, $exit) = $ssh->cmd(" sudo vtysh -c 'sh ip bgp 10.10.3.0'");
print $file $stdout ;

}
close $file ;
my $file_name = 'output.txt';
open (my $file1, '>', 'stat.txt') or die "Could not open file: $!";
#open FH, '+>>', "$file_name.txt" or die "Error:$!\n";
my $output = "sudo vtysh -c 'sh ip bgp 10.10.3.0'";
my $host = "192.168.44.190";
my $user = "isoke";
my $pass = "test123";
my $ssh = Net::SSH::Perl->new( $host );
open(FILE, $file_name) or die "Can't open $file_name: $!";
while (<FILE>) {
if($_=~ m/reuse/)
    {
     # print $_ ;
    my $info =$_;
    print $file1 $info;
}
else {
next ;

}
}
close $file1;
close FILE;
my $statfile_name ='stat.txt';
open(STAT, $statfile_name) or die "Can't open $file_name: $!";
print scalar<STAT>;
while (<STAT>) {
}
close STAT;
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

# BGP configuration sub routine 
sub bgpd_conf{
     my $timeout = 0.1;
     my $expect_log = "/tmp/output.tmp";
     foreach my $s (@{$data->{router}}) {
          if($s->{ns} eq $_[0]){
	       print "***Configuring  Router$s->{name}***\n";
	       print "Interface \n";
	       foreach my $b (@{$s->{interfaces}})
	       {
	            print "	InterfaceName : $b->{InterfaceName} \n";
		    print "	IP Address $b->{interfaceip}/$b->{subnet} \n";
		    print "\n";
	       }
	       print "Configuring OSPF For Router$s->{name} \n";
	       print "	Routerid $s->{routerid} \n"; 
	       foreach my $k (@{$s->{neighbor}})
	       {   
	            print "	neighbor $k->{ip} in AS $k->{asno}\n";
	       }
	       print "        BGP timers enabled \n";
	       print "           Keeplive     $s->{timers}->{keepalive} \n";
	       print "           Holddowntime $s->{timers}->{holddowntime}\n";
	       if($s->{dampeningparameter}->{name} eq "enabled"){
	            print "        BGP Dampening enabled \n";
		    print "           Halflife     $s->{dampeningparameter}->{halflife} \n";
		    print "           Reuselimit   $s->{dampeningparameter}->{reuselimit} \n";
		    print "           Supresslimit $s->{dampeningparameter}->{suppresslimit}\n"; 
		    print "           MaximumSuppresslimit $s->{dampeningparameter}->{maximumsuppresslimit}\n";
	       }
	       if($s->{med}->{name} eq "enabled"){
	            print "        Multi-EXit-Discriminator enabled \n";
		    print "           Metric $s->{med}->{metric} \n";
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
        
               foreach my $h (@{$data->{router}})
               {
                    if($h->{ns} eq $_[0]){
                         foreach my $j (@{$h->{neighbor}}){
                              $exp->expect($timeout, "bgpd(config)#");
                              $exp->send("neighbor $j->{ip} remote-as $j->{asno} \n");
                         }
                    }
               }
        $exp->expect($timeout, "bgpd(config)#");
        $exp->send("$e->{dampeningparameter}->{enable} $e->{dampeningparameter}->{halflife} $e->{dampeningparameter}->{reuselimit} $e->{dampeningparameter}->{suppresslimit} $e->{dampeningparameter}->{maximumsuppresslimit} \n");
          }
     }

     $exp->expect($timeout, "bgpd(config)#");
     $exp->send(" redistribute kernel\n");

     $exp->expect($timeout, "bgpd(config)#");
     $exp->send(" redistribute connected\n");
        
     $exp->expect($timeout, "bgpd#");
     $exp->send("quit\n");
     close(EXPECT);

}
