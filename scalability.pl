#!/usr/bin/perl

#module used
use strict;
use warnings;
use Expect;
use XML::Simple;
use Data::Dumper;
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
my $host = "192.168.44.200";
my $user = "root";
my $password = "test123";
print "Creating Bridge $bridge_name\n";
system ("ovs-vsctl add-br  $bridge_name ");
print"Creating $ARGV[3] VirtualInterfaces as required for the test scenario\n";
for (my $i=1; $i <= $ARGV[3]; $i++){
    system("ip link add tap$i type veth peer name ovs-tap$i" );
    }
system("export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/lib/quagga");
mkdir $existingdir unless -d $existingdir; # Check if dir exists. If not create it.
my  $xml = new XML::Simple (KeyAttr=>[],forcearray=> qr/(interfaces|network)$/);
# read XML file
my $data = $xml->XMLin("scalability.xml");

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

print "Waiting for the dut to learn all the advertised routes\n";
sleep(40);
print "Pinginging all the advertised routes \n";
my ($result,$result1) =ping();
if($result == 0){
     print "Route Verification test is successful \n"; 
     print "Dut can hold $result1 Routes \n";
}
else {
    print "Route verification failed \n";
}

my $ssh1=Net::SSH::Perl->new($host);
$ssh1->login($user,$password);
open (my $file, '>', 'stat.txt') or die "Could not open file: $!";
my($stdout1, $stderr1, $exit1) = $ssh1->cmd("vtysh -c 'sh ip ospf '");
my($stdout2, $stderr2, $exit2) = $ssh1->cmd("vtysh -c 'sh ip ospf route '");
print  $file  $stdout1 ;
print $file $stdout2 ;
close $file;
result();

sub result{
     my $output_file='stat.txt';
     open(FILE, $output_file) or die "Can't open $output_file: $!";
     while (<FILE>) {
         if($_=~ m/Number of LSA/ ){
             print $_ ;
         }

     }
}
sub ping{
     my $host = "192.168.44.200";
     my $user1 = "root";
     my $password1 = "test123";
     my $ssh = Net::SSH::Perl->new($host);
     my $lsa =0;
     my $lsa1=0;
     $ssh->login($user1, $password1);
     open (my $file1, '>', 'output.txt') or die "Could not open file: $!";
     foreach my $a (@{$data->{router}}){
          foreach my $b (@{$a->{interfaces}}){
               utf8::downgrade($b->{interfaceip});
               my($stdout, $stderr, $exit) = $ssh->cmd(" ping -c 2 $b->{interfaceip} " );
               unless ($stdout =~ /(\d+)% packet loss/ ) {
               die ( "Bad Response:\n$stdout\n" );
			}
               print $file1 $stdout;
               my $loss=$1;
               if($loss == 100){
                  $lsa +=1;
               }
               else {
               $lsa1+=1;
             }

          }
     }
     return ($lsa,$lsa1);
}

system ("ovs-vsctl del-br $ARGV[0] ");
system("killall -9 zebra");
#system("killall -9 bgpd");
system("killall -9 ospfd");
system("killall -9 $config");

for(my $i=1 ; $i <=$ARGV[1] ;$i++){
	system("ip netns del NS$i");
	system("rm -rf $existingdir/$ARGV[2]_NS$i.conf");
	system("rm -rf $existingdir/zebra_NS$i.conf");
}    

sub ospfd_conf{
    my $timeout =0.01;
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
                if($g->{InterfaceName} ne "lo"){
                system ("ip link set $g->{InterfaceName} netns $_[0] \n");}
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
    
    $exp->expect($timeout, "ospfd(config)#");
    $exp->send( "router ospf \n");
    foreach my  $e (@{$data->{router}})
    {
        if($e->{ns} eq $_[0]){
            foreach my $m (@{$e->{network}}){
                $exp->expect($timeout, "ospfd(config)#");
		$exp->send("network $m->{ip}/$m->{subnet} area $m->{area}\n");
            }
        }
    }

    $exp->expect($timeout, "ospfd(config)#");
    $exp->send(" redistribute connected\n");
    
    $exp->expect($timeout, "ospfd#");
    $exp->send("quit\n");
    close(EXPECT);
}

