# Copyright 2010-present Basho Technologies, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'spec_helper'
Riak::Client::BeefcakeProtobuffsBackend.configured?

describe Riak::Client::BeefcakeProtobuffsBackend::BucketPropertiesOperator do
  let(:backend_class){ Riak::Client::BeefcakeProtobuffsBackend }
  let(:backend) { instance_double('Riak::Client::BeefcakeProtobuffsBackend') }

  let(:protocol) do
    instance_double('Riak::Client::BeefcakeProtobuffsBackend::Protocol').
      tap do |p|
      allow(backend).to receive(:protocol).and_yield(p)
    end
  end

  let(:bucket_name){ 'bucket_name' }
  let(:bucket) do
    instance_double('Riak::Bucket').tap do |b|
      allow(b).to receive(:name).and_return(bucket_name)
      allow(b).to receive(:is_a?).with(Riak::Bucket).and_return(true)
      allow(b).to receive(:needs_type?).and_return(false)
    end
  end

  let(:test_props) do
    backend_class::RpbBucketProps.
      new(
          n_val: 3,
          pr: 0xffffffff - 1,
          r: 0xffffffff - 2,
          w: 0xffffffff - 3,
          pw: 0xffffffff - 4,
          dw: 0,
          rw: 1,
          precommit: precommit,
          postcommit: backend_class::RpbCommitHook.new(name: 'piper'),
          linkfun: backend_class::RpbModFun.new(module: 'nachos',
                                                function: 'galacticos')
          )
  end

  let(:precommit) do
    backend_class::RpbCommitHook.
      new(
          modfun: backend_class::RpbModFun.new(
                                               module: 'validate_json',
                                               function: 'validate'
                                               ))
  end

  let(:get_bucket_request) do
    backend_class::RpbGetBucketReq.new bucket: bucket_name
  end

  let(:get_bucket_response) do
    backend_class::RpbGetBucketResp.
      new(props: test_props)
  end

  let(:get_bucket_expectation) do
    expect(protocol).to receive(:write).
      with(:GetBucketReq, get_bucket_request)

    expect(protocol).to receive(:expect).
      with(:GetBucketResp,
           backend_class::RpbGetBucketResp).
      and_return(get_bucket_response)
  end

  subject{ described_class.new backend }

  it 'is initialized with a backend' do
    expect{ described_class.new backend }.to_not raise_error
  end

  it 'passes through scalar properties' do
    get_bucket_expectation

    resp = nil
    expect{ resp = subject.get bucket }.to_not raise_error

    expect(resp['n_val']).to eq 3
  end

  describe 'quorums' do
    it 'rubyfies' do
      get_bucket_expectation

      resp = nil
      expect{ resp = subject.get bucket }.to_not raise_error

      expect(resp['pr']).to eq 'one'
      expect(resp['r']).to eq 'quorum'
      expect(resp['w']).to eq 'all'
      expect(resp['pw']).to eq 'default'
      expect(resp['dw']).to eq 0
      expect(resp['rw']).to eq 1
    end

    it 'riakifies' do
      expected_props = backend_class::RpbBucketProps.
        new(
            pr: 0xffffffff - 1,
            r: 0xffffffff - 2,
            w: 0xffffffff - 3,
            pw: 0xffffffff - 4,
            dw: 0,
            rw: 1
            )

      set_bucket_request = backend_class::RpbSetBucketReq.new
      set_bucket_request.bucket = bucket_name
      set_bucket_request.props = expected_props

      expect(protocol).to receive(:write).
        with(:SetBucketReq, set_bucket_request)

      expect(protocol).to receive(:expect).
        with(:SetBucketResp)

      # support both strings and symbols for quorum names
      write_props = {
        pr: 'one',
        r: :quorum,
        w: 'all',
        pw: :default,
        dw: 0,
        rw: 1
      }

      expect{ subject.put bucket, write_props }.to_not raise_error
    end
  end

  describe 'commit hooks' do
    it 'rubyfies' do
      expect(protocol).to receive(:write).
        with(:GetBucketReq, get_bucket_request)

      expect(protocol).to receive(:expect).
        with(:GetBucketResp,
             backend_class::RpbGetBucketResp).
        and_return(get_bucket_response)

      resp = nil
      expect{ resp = subject.get bucket }.to_not raise_error

      expect(resp['precommit']).to be_an Array
      expect(pre = resp['precommit'].first).to be_a Hash
      expect(pre['mod']).to eq 'validate_json'
      expect(pre['fun']).to eq 'validate'

      expect(resp['postcommit'].first).to eq 'piper'
    end

    it 'riakifies' do
      modfun = backend_class::RpbModFun.new(
                                            module: 'validate_json',
                                            function: 'validate'
                                            )
      expected_props = backend_class::RpbBucketProps.
        new(
            precommit:  [backend_class::RpbCommitHook.
                         new(modfun: modfun)],
            postcommit: [backend_class::RpbCommitHook.
                         new(name: 'piper')]
            )

      set_bucket_request = backend_class::RpbSetBucketReq.new
      set_bucket_request.bucket = bucket_name
      set_bucket_request.props = expected_props

      expect(protocol).to receive(:write).
        with(:SetBucketReq, set_bucket_request)

      expect(protocol).to receive(:expect).
        with(:SetBucketResp)

      write_props = {
        precommit: { mod: 'validate_json', fun: 'validate' },
        postcommit: ['piper']
      }

      expect{ subject.put bucket, write_props }.to_not raise_error
    end
  end

  describe 'modfuns' do
    it 'rubyfies' do
      get_bucket_expectation

      resp = nil
      expect{ resp = subject.get bucket }.to_not raise_error

      expect(resp['linkfun']).to eq({
                                           'mod' => 'nachos',
                                           'fun' => 'galacticos'
                                         })

      expect(resp['chash_keyfun']).to_not be
    end

    it 'riakifies' do
      expected_props = backend_class::RpbBucketProps.
        new(
            linkfun: backend_class::RpbModFun.new(module: 'nachos',
                                                  function: 'galacticos')
            )

      set_bucket_request = backend_class::RpbSetBucketReq.new
      set_bucket_request.bucket = bucket_name
      set_bucket_request.props = expected_props

      expect(protocol).to receive(:write).
        with(:SetBucketReq, set_bucket_request)

      expect(protocol).to receive(:expect).
        with(:SetBucketResp)

      write_props = {
        linkfun: { mod: 'nachos', fun: 'galacticos' }
      }

      expect{ subject.put bucket, write_props }.to_not raise_error
    end
  end

  describe 'repl modes' do
    it 'riakifies symbols' do
      expected_props = backend_class::RpbBucketProps.
        new(repl: 2)

      set_bucket_request = backend_class::RpbSetBucketReq.new
      set_bucket_request.bucket = bucket_name
      set_bucket_request.props = expected_props

      expect(protocol).to receive(:write).
        with(:SetBucketReq, set_bucket_request)

      expect(protocol).to receive(:expect).
        with(:SetBucketResp)

      write_props = { repl: :fullsync }

      expect{ subject.put bucket, write_props }.to_not raise_error
    end
  end
end
