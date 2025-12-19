import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

/// Blockchain servisi - Veri doğrulama ve güvenli saklama
class BlockchainService {
  late Web3Client _client;
  late EthereumAddress _contractAddress;
  late DeployedContract _contract;
  late ContractFunction _storeDataFunction;
  late ContractFunction
  _verifyDataFunction; // ignore: unused_field, gelecekte doğrulama çağrısı için ayrıldı

  // Polygon testnet için RPC URL
  static const String _rpcUrl = 'https://rpc-mumbai.maticvigil.com';

  /// Blockchain servisini başlat
  Future<void> initializeBlockchain() async {
    try {
      _client = Web3Client(_rpcUrl, http.Client());

      // Smart contract adresi (testnet için örnek)
      _contractAddress = EthereumAddress.fromHex(
        '0x1234567890123456789012345678901234567890',
      );

      // Contract ABI tanımlama
      final contractAbi = ContractAbi.fromJson(
        _getContractAbi(),
        'ConsumptionContract',
      );
      _contract = DeployedContract(contractAbi, _contractAddress);

      _storeDataFunction = _contract.function('storeConsumptionData');
      _verifyDataFunction = _contract.function('verifyData');

      dev.log(
        'Blockchain servisi başarıyla başlatıldı',
        name: 'BlockchainService',
      );
    } catch (e, st) {
      dev.log(
        'Blockchain başlatma hatası: $e',
        name: 'BlockchainService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Tüketim verilerini blockchain'e kaydet
  Future<String> storeConsumptionData({
    required double electricity,
    required double water,
    required double fuel,
    required double waste,
    required int timestamp,
    required String userId,
  }) async {
    try {
      // Private key (test için - gerçek uygulamada güvenli saklanmalı)
      final credentials = EthPrivateKey.fromHex(
        '0x1234567890123456789012345678901234567890123456789012345678901234',
      );

      // Transaction oluştur
      final transaction = Transaction.callContract(
        contract: _contract,
        function: _storeDataFunction,
        parameters: [
          BigInt.from((electricity * 1000).round()), // Wei cinsinden
          BigInt.from((water * 1000).round()),
          BigInt.from((fuel * 1000).round()),
          BigInt.from((waste * 1000).round()),
          BigInt.from(timestamp),
          userId, // ABI 'string' beklediği için doğrudan string gönderilir
        ],
        gasPrice: EtherAmount.fromBigInt(EtherUnit.gwei, BigInt.from(20)),
        maxGas: 100000,
      );

      // Transaction gönder
      final result = await _client.sendTransaction(
        credentials,
        transaction,
        chainId: 80001, // Polygon Mumbai testnet
      );

      dev.log(
        'Veri blockchain\'e kaydedildi: $result',
        name: 'BlockchainService',
      );
      return result;
    } catch (e, st) {
      dev.log(
        'Blockchain kayıt hatası: $e',
        name: 'BlockchainService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      throw Exception('Veri blockchain\'e kaydedilemedi: $e');
    }
  }

  /// Blockchain'den veri doğruluğunu kontrol et
  Future<bool> verifyData(String transactionHash) async {
    try {
      final receipt = await _client.getTransactionReceipt(transactionHash);

      if (receipt == null) {
        return false;
      }

      // Transaction başarılı mı kontrol et (web3dart: status bool?)
      return receipt.status ?? false;
    } catch (e, st) {
      dev.log(
        'Veri doğrulama hatası: $e',
        name: 'BlockchainService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Blockchain'den tüketim verilerini oku
  Future<Map<String, dynamic>> getConsumptionData(String userId) async {
    try {
      final result = await _client.call(
        contract: _contract,
        function: _contract.function('getConsumptionData'),
        params: [userId],
      );

      if (result.isNotEmpty) {
        return {
          // BigInt -> double dönüşümü
          'electricity': (result[0] as BigInt).toInt() / 1000.0,
          'water': (result[1] as BigInt).toInt() / 1000.0,
          'fuel': (result[2] as BigInt).toInt() / 1000.0,
          'waste': (result[3] as BigInt).toInt() / 1000.0,
          'timestamp': (result[4] as BigInt).toInt(),
          'verified': true,
        };
      }

      return {'verified': false};
    } catch (e, st) {
      dev.log(
        'Veri okuma hatası: $e',
        name: 'BlockchainService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return {'verified': false, 'error': e.toString()};
    }
  }

  /// Karbon ayak izi verilerini blockchain'e kaydet
  Future<String> storeCarbonFootprint({
    required double dailyEmission,
    required double monthlyEmission,
    required double yearlyEmission,
    required int timestamp,
    required String userId,
  }) async {
    try {
      final credentials = EthPrivateKey.fromHex(
        '0x1234567890123456789012345678901234567890123456789012345678901234',
      );

      final transaction = Transaction.callContract(
        contract: _contract,
        function: _contract.function('storeCarbonFootprint'),
        parameters: [
          BigInt.from((dailyEmission * 1000).round()),
          BigInt.from((monthlyEmission * 1000).round()),
          BigInt.from((yearlyEmission * 1000).round()),
          BigInt.from(timestamp),
          userId,
        ],
        gasPrice: EtherAmount.fromBigInt(EtherUnit.gwei, BigInt.from(20)),
        maxGas: 100000,
      );

      final result = await _client.sendTransaction(
        credentials,
        transaction,
        chainId: 80001,
      );

      return result;
    } catch (e, st) {
      dev.log(
        'Karbon ayak izi kayıt hatası: $e',
        name: 'BlockchainService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      throw Exception('Karbon ayak izi verisi kaydedilemedi: $e');
    }
  }

  /// Blockchain durumunu kontrol et
  Future<Map<String, dynamic>> getBlockchainStatus() async {
    try {
      final blockNumber = await _client.getBlockNumber();
      final gasPrice = await _client.getGasPrice();

      return {
        'connected': true,
        'blockNumber': blockNumber,
        'gasPrice': gasPrice.getInWei,
        'network': 'Polygon Mumbai Testnet',
        'contractAddress': _contractAddress.hex,
      };
    } catch (e) {
      return {'connected': false, 'error': e.toString()};
    }
  }

  /// Smart contract ABI tanımı
  String _getContractAbi() {
    return '''
    [
      {
        "inputs": [
          {"name": "electricity", "type": "uint256"},
          {"name": "water", "type": "uint256"},
          {"name": "fuel", "type": "uint256"},
          {"name": "waste", "type": "uint256"},
          {"name": "timestamp", "type": "uint256"},
          {"name": "userId", "type": "string"}
        ],
        "name": "storeConsumptionData",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {"name": "dailyEmission", "type": "uint256"},
          {"name": "monthlyEmission", "type": "uint256"},
          {"name": "yearlyEmission", "type": "uint256"},
          {"name": "timestamp", "type": "uint256"},
          {"name": "userId", "type": "string"}
        ],
        "name": "storeCarbonFootprint",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [{"name": "userId", "type": "string"}],
        "name": "getConsumptionData",
        "outputs": [
          {"name": "electricity", "type": "uint256"},
          {"name": "water", "type": "uint256"},
          {"name": "fuel", "type": "uint256"},
          {"name": "waste", "type": "uint256"},
          {"name": "timestamp", "type": "uint256"}
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [{"name": "transactionHash", "type": "bytes32"}],
        "name": "verifyData",
        "outputs": [{"name": "isValid", "type": "bool"}],
        "stateMutability": "view",
        "type": "function"
      }
    ]
    ''';
  }

  /// Servisi kapat
  void dispose() {
    _client.dispose();
  }
}
