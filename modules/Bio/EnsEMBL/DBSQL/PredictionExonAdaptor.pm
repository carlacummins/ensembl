#EnsEMBL PredictionExon reading writing adaptor for mySQL
#
# Copyright EMBL-EBI 2003
#
# Author: Arne Stabenau
# 
#

=head1 NAME

Bio::EnsEMBL::DBSQL::PredictionExonAdaptor - Performs database interaction for
PredictionExons.

=head1 SYNOPSIS

$pea = $database_adaptor->get_PredictionExonAdaptor();
$pexon = $pea->fetch_by_dbID();

my $slice = $database_adaptor->get_SliceAdaptor->fetch_by_region('X',1,1e6);

my @pexons = @{$pea->fetch_all_by_Slice($slice)};


=head1 CONTACT

  Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=head1 APPENDIX

  The rest of the documentation describes object methods.

=cut


package Bio::EnsEMBL::DBSQL::PredictionExonAdaptor;

use vars qw( @ISA );
use strict;


use Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor;
use Bio::EnsEMBL::PredictionExon;
use Bio::EnsEMBL::Utils::Exception qw( warning throw deprecate );

@ISA = qw( Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor );


#_tables
#
#  Arg [1]    : none
#  Example    : none
#  Description: PROTECTED implementation of superclass abstract method
#               returns the names, aliases of the tables to use for queries
#  Returntype : list of listrefs of strings
#  Exceptions : none
#  Caller     : internal
#

sub _tables {
  return ([ 'prediction_exon', 'pe' ] );
}



#_columns
#
#  Arg [1]    : none
#  Example    : none
#  Description: PROTECTED implementation of superclass abstract method
#               returns a list of columns to use for queries
#  Returntype : list of strings
#  Exceptions : none
#  Caller     : internal

sub _columns {
  my $self = shift;

  return qw( pe.prediction_exon_id
             pe.seq_region_id
             pe.seq_region_start
             pe.seq_region_end
             pe.seq_region_strand
             pe.start_phase
             pe.score
             pe.p_value );
}


# _final_clause
#
#  Arg [1]    : none
#  Example    : none
#  Description: PROTECTED implementation of superclass abstract method
#               returns a default end for the SQL-query (ORDER BY)
#  Returntype : string
#  Exceptions : none
#  Caller     : internal

sub _final_clause {
  return "ORDER BY pe.prediction_transcript_id, pe.exon_rank";
}


=head2 fetch_all_by_PredictionTranscript

  Arg [1]    : Bio::EnsEMBL::PredcitionTranscript $transcript
  Example    : none
  Description: Retrieves all Exons for the Transcript in 5-3 order
  Returntype : listref Bio::EnsEMBL::Exon on Transcript slice 
  Exceptions : none
  Caller     : Transcript->get_all_Exons()

=cut

sub fetch_all_by_PredictionTranscript {
  my ( $self, $transcript ) = @_;

  my $constraint = "pe.prediction_transcript_id = ".$transcript->dbID();

  my $exons = $self->generic_fetch( $constraint );

  if( ! @$exons ) { return [] }

  my @new_exons = map { $_->transfer( $transcript->slice() ) } @$exons;

  return \@new_exons;
}



=head2 store

  Arg [1]    : Bio::EnsEMBL::PredictionExon $exon
               The exon to store in this database
  Arg [2]    : int $prediction_transcript_id
               The internal identifier of the prediction exon that that this
               exon is associated with.
  Arg [3]    : int $rank
               The rank of the exon in the transcript (starting at 1)
  Example    : $pexon_adaptor->store($pexon, 1211, 2);
  Description: Stores a PredictionExon in the database
  Returntype : none
  Exceptions : thrown if exon does not have a slice attached
               or if $exon->start, $exon->end, $exon->strand, or $exon->phase 
               are not defined or if $exon is not a Bio::EnsEMBL::PredictionExon 
  Caller     : general

=cut

sub store {
  my ( $self, $pexon, $pt_id, $rank ) = @_;

  if(!ref($pexon) || !$pexon->isa('Bio::EnsEMBL::PredictionExon') ) {
    throw("Expected PredictionExon argument");
  }

  throw("Expected PredictionTranscript id argument.") if(!$pt_id);
  throw("Expected rank argument.") if(!$rank);

  my $db = $self->db();

  if($pexon->is_stored($db)) {
    warning('PredictionExon is already stored in this DB.');
    return $pexon->dbID();
  }

  if( ! $pexon->start || ! $pexon->end ||
      ! $pexon->strand || ! defined $pexon->phase ) {
    throw("PredictionExon does not have all attributes to store");
  }

  my $slice_adaptor = $db->get_SliceAdaptor();

  my $slice = $pexon->slice();
  if( !ref($slice) || !$slice->isa('Bio::EnsEMBL::Slice') ) {
    throw("PredictionExon must have slice to be stored");
  }

  #maintain reference to original passed-in prediction exon
  my $original = $pexon;

  # make sure that the feature coordinates are relative to
  # the start of the seq_region that the prediction transcript is on
  if($slice->start != 1 || $slice->strand != 1) {
    #move the feature onto a slice of the entire seq_region
    $slice = $slice_adaptor->fetch_by_region($slice->coord_system->name(),
                                             $slice->seq_region_name(),
                                             undef,undef, undef,
                                             $slice->coord_system->version());

    $pexon = $pexon->transfer($slice);

    if(!$pexon) {
      throw('Could not transfer PredictionExon to slice of ' .
            'entire seq_region prior to storing');
    }
  }

  my $seq_region_id = $slice_adaptor->get_seq_region_id( $slice );

  if( ! $seq_region_id ) {
    throw( "Attached slice is not valid in database" );
  }

  my $sth = $db->prepare
    ("INSERT into exon (prediction_transcript_id, exon_rank, " .
                       "seq_region_id, seq_region_start, seq_region_end, " .
                       "seq_region_strand, start_phase, score, p_value)" .
      "VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ? )");

  $sth->execute( $pt_id,
                 $rank,
                 $seq_region_id,
                 $pexon->start(),
                 $pexon->end(),
                 $pexon->strand(),
                 $pexon->phase(),
                 $pexon->score(),
                 $pexon->p_value());

  my $dbID = $sth->{'mysql_insertid'};

  #set the adaptor and dbID of the object they passed in
  $original->dbID($dbID);
  $original->adaptor($self);

  return $dbID;
}



=head2 remove

  Arg [1]    : Bio::EnsEMBL::PredictionExon $exon
               the exon to remove from the database 
  Example    : $exon_adaptor->remove($exon);
  Description: Removes an exon from the database
  Returntype : none
  Exceptions : none
  Caller     : general

=cut

sub remove {
  my $self = shift;
  my $pexon = shift;

  my $db = $self->db();

  if(!$pexon->is_stored($db)) {
    warning('PredictionExon is not in this DB - not removing');
    return undef;
  }

  my $sth = $self->prepare( "delete from exon where exon_id = ?" );
  $sth->execute( $pexon->dbID );

  $pexon->dbID(undef);
  $pexon->adaptor(undef);
}



=head2 list_dbIDs

  Arg [1]    : none
  Example    : @exon_ids = @{$exon_adaptor->list_dbIDs()};
  Description: Gets an array of internal ids for all exons in the current db
  Returntype : list of ints
  Exceptions : none
  Caller     : ?

=cut

sub list_dbIDs {
   my ($self) = @_;

   return $self->_list_dbIDs("prediction_exon");
}



#_objs_from_sth

#  Arg [1]    : Hashreference $hashref
#  Example    : none 
#  Description: PROTECTED implementation of abstract superclass method.
#               responsible for the creation of Genes 
#  Returntype : listref of Bio::EnsEMBL::Genes in target coordinate system
#  Exceptions : none
#  Caller     : internal
#

sub _objs_from_sth {
  my ($self, $sth, $mapper, $dest_slice) = @_;

  #
  # This code is ugly because an attempt has been made to remove as many
  # function calls as possible for speed purposes.  Thus many caches and
  # a fair bit of gymnastics is used.
  #

  my $sa = $self->db()->get_SliceAdaptor();

  my @exons;
  my %slice_hash;
  my %sr_name_hash;
  my %sr_cs_hash;

  my($prediction_exon_id,$seq_region_id,
     $seq_region_start, $seq_region_end, $seq_region_strand,
     $start_phase, $score, $p_value);

  $sth->bind_columns(\$prediction_exon_id,\$seq_region_id,
     \$seq_region_start, \$seq_region_end, \$seq_region_strand,
     \$start_phase, \$score, \$p_value);

  my $asm_cs;
  my $cmp_cs;
  my $asm_cs_vers;
  my $asm_cs_name;
  my $cmp_cs_vers;
  my $cmp_cs_name;
  if($mapper) {
    $asm_cs = $mapper->assembled_CoordSystem();
    $cmp_cs = $mapper->component_CoordSystem();
    $asm_cs_name = $asm_cs->name();
    $asm_cs_vers = $asm_cs->version();
    $cmp_cs_name = $cmp_cs->name();
    $asm_cs_vers = $cmp_cs->version();
  }

  my $dest_slice_start;
  my $dest_slice_end;
  my $dest_slice_strand;
  my $dest_slice_length;
  if($dest_slice) {
    $dest_slice_start  = $dest_slice->start();
    $dest_slice_end    = $dest_slice->end();
    $dest_slice_strand = $dest_slice->strand();
    $dest_slice_length = $dest_slice->length();
  }

  FEATURE: while($sth->fetch()) {
    my $slice = $slice_hash{"ID:".$seq_region_id};

    if(!$slice) {
      $slice = $sa->fetch_by_seq_region_id($seq_region_id);
      $slice_hash{"ID:".$seq_region_id} = $slice;
      $sr_name_hash{$seq_region_id} = $slice->seq_region_name();
      $sr_cs_hash{$seq_region_id} = $slice->coord_system();
    }

    #
    # remap the feature coordinates to another coord system 
    # if a mapper was provided
    #
    if($mapper) {
      my $sr_name = $sr_name_hash{$seq_region_id};
      my $sr_cs   = $sr_cs_hash{$seq_region_id};

      ($sr_name,$seq_region_start,$seq_region_end,$seq_region_strand) =
        $mapper->fastmap($sr_name, $seq_region_start, $seq_region_end,
			 $seq_region_strand, $sr_cs);

      #skip features that map to gaps or coord system boundaries
      next FEATURE if(!defined($sr_name));

      #get a slice in the coord system we just mapped to
      if($asm_cs == $sr_cs || ($asm_cs != $sr_cs && $asm_cs->equals($sr_cs))) {
        $slice = $slice_hash{"NAME:$sr_name:$cmp_cs_name:$cmp_cs_vers"} ||=
          $sa->fetch_by_region($cmp_cs_name, $sr_name,undef, undef, undef,
                               $cmp_cs_vers);
      } else {
        $slice = $slice_hash{"NAME:$sr_name:$asm_cs_name:$asm_cs_vers"} ||=
          $sa->fetch_by_region($asm_cs_name, $sr_name, undef, undef, undef,
                               $asm_cs_vers);
      }
    }

    #
    # If a destination slice was provided convert the coords
    # If the dest_slice starts at 1 and is foward strand, nothing needs doing
    #
    if($dest_slice && ($dest_slice_start != 1 || $dest_slice_strand != 1)) {
      if($dest_slice_strand == 1) {
        $seq_region_start = $seq_region_start - $dest_slice_start + 1;
        $seq_region_end   = $seq_region_end   - $dest_slice_start + 1;
      } else {
        my $tmp_seq_region_start = $seq_region_start;
        $seq_region_start = $dest_slice_end - $seq_region_end + 1;
        $seq_region_end   = $dest_slice_end - $tmp_seq_region_start + 1;
        $seq_region_strand *= -1;
      }

      $slice = $dest_slice;

      #throw away features off the end of the requested slice
      if($seq_region_end < 1 || $seq_region_start > $dest_slice_length) {
        next FEATURE;
      }
    }

    #finally, create the new PredictionExon
    push @exons, Bio::EnsEMBL::PredictionExon->new
      ( '-start'         =>  $seq_region_start,
        '-end'           =>  $seq_region_end,
        '-strand'        =>  $seq_region_strand,
        '-adaptor'       =>  $self,
        '-slice'         =>  $slice,
        '-dbID'          =>  $prediction_exon_id,
        '-phase'         =>  $start_phase,
        '-score'         =>  $score,
        '-p_value'       =>  $p_value);
  }

  return \@exons;
}


1;
