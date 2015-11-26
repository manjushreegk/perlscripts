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
my $count =1;
my $intfile="int.txt";
my $statfile="stat.txt";
my $total = 0;
my $trial = 0;

print"Creating $ARGV[3] VirtualInterfaces \n";
for (my $i=1; $i <= $ARGV[3]; $i++){
    system("ip link add tap$i type veth peer name ovs-tap$i" );
    }
mkdir $existingdir unless -d $existingdir; # Check if dir exists. If not create it.
my  $xml = new XML::Simple (KeyAttr=>[],forcearray=> qr/(interfaces|neighbor)$/);
# read XML file
my $data = $xml->XMLin("convergence.xml");

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
open(my $int ,'>','int.txt') or die "could not openfile :$!";
foreach my $a (@{$data->{router}}) {
      if($a->{flap}->{name} eq "enabled"){
        print $int $a->{flap}->{interface} ;
        print $int "\t";
        print $int $a->{ns};
        print $int "\n";
        print $int $a->{flap}->{interface1};
        print $int "\t";
        print $int $a->{ns};
        print $int "\n";
       }
}
close $int;
print "Waiting for the dut to learn all the routes \n";
sleep(50);
open (my $stat, '>', 'stat.txt') or die "Could not open file: $!";
open(INTERFACE,$intfile) or die ("could not open the file $intfile \n");
while(<INTERFACE>){
     (my $interface,my $ns) = split(/\t/,$_);
     print "Withdrawing route$count ........... \n"; 
     my $b=threads->create(\&ping);
     my $c=threads->create(\&flap1,$interface,$ns);
     my $average =$b->join();
     $c->join();
     $count++;
     print $stat $average ;
     print $stat "\n";
     print "\n";
     sleep(30);
}
close $stat;
close INTERFACE;
open(STAT,$statfile) or die ("could not open the file $statfile \n");
print "Calculating average convergence time for all the routes withdrawn \n";
while(<STAT>){
  
     $total += $_ ;
     $trial += 1;
} 
print "The Avgerage Convergence Time  is ",$total/$trial ," ","sec","\n";


sub flap1{
     (my $interfacename,my $nsname) = @_;
     if($nsname =~ m/(\d+)/)  {
          system qq(ip netns exec NS$1 ifconfig $interfacename down);
          sleep(20);
          system qq(ip netns exec NS$1 ifconfig $interfacename up);
     }
}

sub ping {
    my $packet_trans =0;
    my  $packet_rcvd =0;
    print "Calculating Convergence time while Route$count is Withdrawn \n"; 
    open (my $file, '>', 'result.txt') or die "Could not open file: $!";
    my $stdout =`ip netns exec NS1 ping -c 20 70.70.70.1 | grep 'packet loss' ` ;
    unless ($stdout =~ /(\d+)% packet loss/ ) {
       die ( "Bad Response:\n $stdout\n" );
    }
    print $file $stdout; 
    my $loss = $1;
    my @array1 =split(/\,/,$stdout);
    my ($num1 ,$packet1 ,$trans1 )=split(/\ /,$array1[0]);
    my ($space1 ,$packets1 ,$recved1 )=split(/\ /,$array1[1]);
    $packet_trans +=$num1;
    $packet_rcvd +=$packets1;
    $count +=1;
    my $convergence = ($packet_trans - $packet_rcvd) *2;
    my $lost = $packet_trans-$packet_rcvd;
    print "Total no of Packet transmitted : $packet_trans \n" ;
    print "Total no of Packet lost : $lost \n";
    print "Convergence time : $convergence sec \n";
    return $convergence ;
    threads->exit();
}
    
#Delete all the configuration and clearing all the process 
#system ("ovs-vsctl del-br $ARGV[0] ");
print "Stopping bgp process \n";
system("killall -9 zebra");
system("killall -9 $config");
print "Clearing all the config files \n";
for(my $i=1 ; $i <=$ARGV[1] ;$i++){
	system("ip netns del NS$i");
	system("rm -rf $existingdir/$ARGV[2]_NS$i.conf");
	system("rm -rf $existingdir/zebra_NS$i.conf");
}    

# ospf configuration sub routine 
sub ospfd_conf{
    my $timeout = 0.1;
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
               print "Configuring OSPF For Router$a->{name} \n";
               print "	Routerid $a->{routerid} \n"; 
               foreach my $k (@{$a->{network}})
               {   
                   print "	network $k->{ip}/$k->{subnet} in area $k->{area}\n";
               }
         }
    }   
    foreach my $f (@{$data->{router}})
    {
        if($f->{ns} eq $_[0]){
            foreach my $g (@{$f->{interfaces}}){
                if($g->{InterfaceName} ne 'lo'){ 
                    system ("ip link set $g->{InterfaceName} netns $_[0] \n");
                }
                system ("ip netns exec $_[0] ip add add $g->{interfaceip}/$g->{subnet} dev $g->{InterfaceName} \n");
                system ("ip netns exec $_[0] ifconfig $g->{InterfaceName} up \n"); 
            }
        }
    }
    print"**************************************************************************************\n";
    unless(open EXPECT, ">>","$expect_log"){
         die ("Cannot open the expect log file: $expect_log $!\n");
     }
    my $exp = Expect->spawn("ip netns exec  $_[0]  telnet localhost 2604");
    $exp->log_stdout(0);
    $exp->log_file("$expect_log");

    $exp->expect($timeout, "Password:");
    $exp->send("zebra\n");

    $exp->expect($timeout, "ospfd>");
    $exp->send("enable\n");

    $exp->expect($timeout, "ospfd#");
    $exp->send("show run\n");

    $exp->expect($timeout, "ospfd#");
    $exp->send("configure terminal\n");
    foreach my  $e (@{$data->{router}})
    {
        if($e->{ns} eq $_[0]){
            foreach my $m (@{$e->{interfaces}}){
	        if($m->{additionalparameter}->{name} eq 'enabled' ){
                    $exp->expect($timeout, "ospfd(config)#");
                    $exp->send( "interface $m->{InterfaceName} \n");

	            $exp->expect($timeout, "ospfd(config)#");
                    $exp->send("ip ospf hello-interval $m->{additionalparameter}->{hellointerval}\n");
                    
                    $exp->expect($timeout, "ospfd(config)#");
                    $exp->send("ip ospf dead-interval $m->{additionalparameter}->{deadinterval}\n");
						
                    $exp->expect($timeout, "ospfd(config)#");
                    $exp->send("ip ospf retransmit-interval $m->{additionalparameter}->{retransmitinterval}\n");
						
                    $exp->expect($timeout, "ospfd(config)#");
		    $exp->send("ip ospf cost $m->{additionalparameter}->{cost}\n");
	        }
	    }
				
            foreach my $h (@{$data->{router}})
            {
                if($h->{ns} eq $_[0]){
                    foreach my $j (@{$h->{network}}){
                        $exp->expect($timeout, "ospfd(config-if)#");
			$exp->send("quit\n");
		        
                        $exp->expect($timeout, "ospfd(config)#");
		        $exp->send("router ospf\n");
		        
                        $exp->expect($timeout, "ospfd(config)#");
		        $exp->send("network $j->{ip}/$j->{subnet} area $j->{area}\n");
		    }
                }
           } 
           if ($e->{capacity}->{name} eq 'enabled'){
                    my $list = $e->{capacity}->{ipaddress};
                    my @network =split(/\./,$list);
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
                         $exp->expect($timeout, "ospfd(config-router)#");
                         $exp->send("network $network[0].$network[1].$network[2].$network[3]/24\n");
                         $network[2]++;
                         }
                    }

             $exp->expect($timeout, "ospfd(config)#");
             $exp->send(" redistribute connected\n");
        
             $exp->expect($timeout, "ospfd#");
             $exp->send("quit\n");
             close(EXPECT);
        }
    }
}

