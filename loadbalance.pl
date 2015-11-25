#!/usr/bin/perl -w

#module used
use strict;
use warnings;
use Expect;
use XML::Simple;
use Data::Dumper;
use threads;
#use Net::SSH::Perl;
my $bridge_name =$ARGV[0];
#my $existingdir = $ARGV[2];
my $existingdir = "/etc/quagga";
my $network3 = 1;
my $network2 = 1;
my $network1 = 10;
my $ip3 = 1;
my $ip4 =0;
my $config = $ARGV[3];
my $bgpd = "bgpd";
my $ospfd = "ospfd";
my $ripd = "ripd";
my $physicalports=$ARGV[1];
my $routes=$ARGV[2]+1;
my $ns=$ARGV[1]*$routes+2;
my $virtualinterface=($ns-$ARGV[1]-2) *2 ;
my $output_file = 'newfile.txt';
my $packet_count=0;
my  ($Ifacename,$MTU,$Met,$RXOK,$RXERR,$RXDRP,$RXOVR,$TXOK,$TXERR,$TXDRP,$TXOVR,$Flg);
print "Creating Bridge $bridge_name\n";
system ("ovs-vsctl add-br  $bridge_name ");
print"Creating $virtualinterface VirtualInterfaces as required for the test scenario\n";
for (my $i=1; $i <= $virtualinterface; $i++){
    system("ip link add tap$i type veth peer name ovs-tap$i" );
    }
#system("export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/lib/quagga");
mkdir $existingdir unless -d $existingdir; # Check if dir exists. If not create it.
my  $xml = new XML::Simple (KeyAttr=>[],forcearray=> qr/(interfaces|network)$/);
# read XML file
my $data = $xml->XMLin("loadbalance.xml");

for (my $i=1; $i <= $ns; $i++){
        
        print "\n";        
        print "*******Adding Router R$i ************ \n";
        system ("ip netns add NS$i ");
    	print "Creating Configuration file for namespace NS$i\n ";
        my  $br_file = "$ARGV[2]_NS$i.conf";
        my  $zr_file = "zebra_NS$i.conf";
        unless(open BR_FILE ,">>", "$existingdir/$ARGV[3]_NS$i.conf" ){
            die "Can't open '$existingdir/$ARGV[3]_NS$i.conf'\n";
        }

        unless(open ZR_FILE ,">>", "$existingdir/zebra_NS$i.conf" ){
            die "Can't open '$existingdir/zebra_NS$i.conf'\n";
        }
       
        print BR_FILE "password zebra\n";
        print BR_FILE "line vty\n";
        close BR_FILE;
        print ZR_FILE "password zebra\n";
        print ZR_FILE "line vty\n";
        close ZR_FILE;
        system("ip netns exec NS$i zebra -f $existingdir/zebra_NS$i.conf -i /var/run/quagga/zebra_NS$i.pid -d");
        system("ip netns exec NS$i $ARGV[3] -f $existingdir/$ARGV[3]_NS$i.conf  -i /var/run/quagga/$ARGV[3]_NS$i.pid -d");
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
print"waiting for the dut to learn all the routes \n";
sleep(120);

open (my $file, '>', 'file.txt') or die "Could not open file: $!";
my $stdout =`ip netns exec NS11 netstat -i `;
print $file $stdout;
`sed 1d file.txt > newfile.txt` ;
close $file;

my $f = threads->create(\&ping);
my (@iface) = initThreads();
foreach  (@iface){
     my $name; 
     $_ = threads->create(\&capture,$name);
}

foreach(@iface){
     $_->join();
}
$f->join();
my(@int)=initThreads();
foreach(@int){
     $_=threads->create(\&stats);
}
#sub module to count number of captured packets 
sub stats{
     open (my $file1, '>', "pcap$_") or die "Could not open file: $!";
     my $output=`tcpdump -r $_  icmp[icmptype] == 0 `;
     print $file1  $output;
     close $file1;
     
     my $statfile="pcap$_";
     my $tapname =$_;
     open(FILE,$statfile) or die "can't open $statfile: $!";
     while(<FILE>){
          $packet_count++;
   
     }
     my ($ovs,$tap)=split(/\-/,$tapname);
     foreach my $a (@{$data->{router}}) {
          foreach my $b (@{$a->{interfaces}}){
               if($b->{InterfaceName} eq $tap){
                    print "No of packets received  on router $a->{name} is $packet_count\n";
               }
          }
     }
     threads->exit();
}

foreach(@int){
     $_->join();
}
sub ping{
    `ip netns exec NS1 ping -c 150 9.9.9.9`;
    threads->exit();
    }
#sub module to initiate threads 
sub initThreads{
     open(FILE, $output_file) or die "Can't open $output_file: $!";
     my $i;
     my @initThreads;
     my @interface;
     my $count;
     while (<FILE>) {
          ($Ifacename,$MTU,$Met,$RXOK,$RXERR,$RXDRP,$RXOVR,$TXOK,$TXERR,$TXDRP,$TXOVR,$Flg)=split;
           if($Ifacename ne 'Iface'){
                if($Ifacename ne 'lo'){
                     $count ++;
                     push (@interface,$Ifacename) ;        
                }
           }
      }
      for(my $i = 1;$i<=$count;$i++){
           push(@initThreads,$i);
      }
      return (@interface);
}
#sub module to capture the packets on the destination interfaces 
sub capture{
     my $int_name = $_;
     system("ip netns exec NS11 tcpdump -i $int_name -w $int_name  &");
     sleep(120);
     system(q/kill -9 `ps -ef | grep tcpdump | grep -v grep | awk '{print $2}'`/);
     threads->exit();
}
#Delete all the configuration and clearing all the process 
#system ("ovs-vsctl del-br $ARGV[0] ");
system("killall -9 zebra");
#system("killall -9 bgpd");
system("killall -9 ospfd");
system("killall -9 $config");

for(my $i=1 ; $i <=$ns ;$i++){
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

