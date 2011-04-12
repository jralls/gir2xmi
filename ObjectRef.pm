#!/usr/bin/perl -w
#-*- mode: perl; -*-
use strict;

package ObjectRef;

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Carp qw(cluck carp);

our $curl = "http://www.gtk.org/introspection/c/1.0";

sub new {
    my ($c_name) = @_;
    my $class = ref($c_name) || $c_name;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub exists {
    my ($self, $name) = @_;
    return 0 unless $name;
#    warn "$name exists in registry" if exists $$self{name};
#    warn "$name is an alias for $$self{aliases}{$name}"
#	if exists $$self{aliases}{$name};
    return exists $$self{$name} ||
	exists $$self{aliases}{$name} && exists $$self{$$self{aliases}{$name}};
}

#Make a unique id, combining an item name with a qualifier and adding
#the current time-value as a seed, then pushing it through MD5 to make
#a nice identifier.
sub make_id {
    my ($self, $name, $qualifier) = @_;
    die "Can't make an id with no name" unless $name;
    my $salt = rand();
    $qualifier = "foo" unless $qualifier;
    return md5_hex("$qualifier.$name.$salt");
}

sub register_object {
    my ($self, $type, $name, $real) = @_;
#    $self->debug(Data::Dumper->Dump([$self], ["ObjectRef"])) if $debug > 5;
    die "Can't make an id with no name" unless $name;
    cluck "Can't make an id with no type" unless $type;
    $$self{$name} = {} unless exists $$self{$name};
    my $entry = $$self{$name};
    if ($$entry{type} && $$entry{type} ne $type &&
	$$entry{type} ne "Temporary") {
	carp ("Attempt to register existing object $$entry{type}:$name with new type $type");
	return $$entry{id};
    }
    $$entry{real} = $$entry{real} || $real ? 1 : 0;
    $$entry{type} = $type ? $type : "Temporary";
    $$entry{id} = $self->make_id($name, $type) unless $$entry{id};

    return $$entry{id};
}

sub object_id {
    my ($self, $type, $name) = @_;
    die "No $self" unless $self;
    die "Aliases not initialized" unless exists $$self{aliases};
    cluck "No name passed in to object_id" unless $name;

    $name = $$self{aliases}{$name} if exists $$self{aliases}{$name};
    if (exists $$self{$name}) {
	return $$self{$name}{id};
    }
    return $self->register_object($type, $name);
}

sub object_type {
    my ($self, $name) = @_;
    return undef unless $name;
    $name = $$self{aliases}{$name} if exists $$self{aliases}{$name};
    return undef unless exists $$self{$name};
    return $$self{$name}{type};
}

sub register_alias {
    my ($self, $element) = @_;
    my $name = $element->getAttribute("name") or return;
    my $typeattr = $element->getAttributeNS($curl, "type") or return;

    $$self{aliases}{$typeattr} = $name;
}

sub get_unregistered {
    my ($self) = @_;
    my $list = [];
    foreach my $name (keys %$self) {
	next if $$self{$name}{real};
	next if $name eq "aliases";
	my $hash = $$self{$name};
	$$hash{name} = $name;
	push @$list, $hash;
    }
    return $list;
}

sub change_type {
    my ($self, $name, $new_type) = @_;
    $$self{$name}{type} = $new_type;
}
1;
