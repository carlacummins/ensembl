#

=head1 NAME

Bio::EnsEMBL::Utils::EasyArgv

=head1 SYNOPSIS

    use Bio::EnsEMBL::Utils::EasyArgv;
    my $db = get_ens_db_from_argv; # this method is exported.
    use Getopt::Long;
    my ($others);
    &GetOptions(
        'others=s' => \$others
    );

=head1 DESCRIPTION

This is a lazy but easy way to get the db-related arguments. All you need to do
is to invoke get_ens_db_from_argv before using standard Getopt. The below 
options will be absorbed and removed from @ARGV.

db_file, host, db_host, dbhost, user, db_user, dbuser, pass, db_pass, dbpass,
dbname, db_name.

Now you can take advantage of Perl's do method to execute a file as perl script and get returned the last line of it. For your most accessed db setting, you 
can have a file named, say, ensdb_homo_core_18.perlobj, with the content like

    use strict;  # The ceiling line
    use Bio:: EnsEMBL::DBSQL::DBAdaptor;
    my $db = Bio:: EnsEMBL::DBSQL::DBAdaptor->new(
        -host => 'ensembldb.ensembl.org',
        -user => 'anonymous',
        -dbname => 'homo_sapiens_core_18_34'
        );
    $db;  # The floor line

In the your command line, you just need to write like 

perl my_script.pl -db_file ensdb_homo_core_18.perlobj

rather than verbose 

-host ensembldb.ensembl.org -user anonymous -dbname homo_sapiens_core_18_34


=head1 AUTHOR

Juguang XIAO, juguang@tll.org.sg

Other contributors' names here.

=cut

use strict;

package Bio::EnsEMBL::Utils::EasyArgv;
use vars qw(@ISA @EXPORT);
use vars qw($debug);
use Exporter ();
@ISA= qw(Exporter);
@EXPORT = qw(get_ens_db_from_argv
);
use Bio::Root::Root; # For _load_module
use Getopt::Long;

sub _debug_print;

sub get_ens_db_from_argv {
    my ($db_file, $host, $user, $pass, $dbname, $db_module);
    $host = 'localhost';
    $db_module = 'Bio::EnsEMBL::SQL::DBAdaptor';
    Getopt::Long::config('pass_through');
    &GetOptions(
        'db_file=s' => \$db_file,
        'host|dbhost|db_host=s' => \$host,
        'user|dbuser|db_user=s' => \$user,
        'pass|dbpass|db_pass=s' => \$pass,
        'dbname|db_name=s' => \$dbname,
        'db_module=s' => \$db_module
    );

    my $db;
    if(defined $db_file){
        -e $db_file or die "'$db_file' is defined but does not exist\n";
        eval { $db = do($db_file) };
        $@ and die "'$db_file' is not a perlobj file\n";
        $db->isa('Bio::EnsEMBL::DBSQL::DBAdaptor')
            or die "'$db_file' is not EnsEMBL DBAdaptor\n";
        _debug_print "I get a db from file\n";
        
    }elsif(defined $host && defined $user && defined $dbname){
        Bio::Root::Root::_load_module($db_module);
        $db = $db_module->new(
            -host => $host,
            -user => $user,
            -pass => $pass,
            -dbname => $dbname
        );
    }else{
        die "Cannot get the db, due to the insufficient information\n";
    }
    return $db;
}

sub _debug_print {
    print STDERR @_ if $debug;
}


1;
