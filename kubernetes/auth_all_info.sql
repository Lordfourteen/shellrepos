/*
 Navicat Premium Data Transfer

 Source Server         : 172.168.3.140
 Source Server Type    : MySQL
 Source Server Version : 50721
 Source Host           : 172.168.3.140:3306
 Source Schema         : mlpltf

 Target Server Type    : MySQL
 Target Server Version : 50721
 File Encoding         : 65001

 Date: 11/04/2018 16:36:30
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for auth_all_info
-- ----------------------------
DROP TABLE IF EXISTS `auth_all_info`;
CREATE TABLE `auth_all_info`  (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `auth_end_datetime` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `auth_num` int(11) NOT NULL,
  `auth_type` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `is_expired` int(11) NOT NULL,
  `md5` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NULL DEFAULT NULL,
  `update_time` varchar(255) NULL DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 34 CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Records of auth_all_info
-- ----------------------------
INSERT INTO `auth_all_info` VALUES (31, NULL, 0, 'CPU', 0, '8c643d86e3bc0ce5eb970f20f720db62', NULL);
INSERT INTO `auth_all_info` VALUES (32, NULL, 0, 'GPU', 0, '8c643d86e3bc0ce5eb970f20f720db62', NULL);
INSERT INTO `auth_all_info` VALUES (33, NULL, 0, 'STORAGE', 0, '8c643d86e3bc0ce5eb970f20f720db62', NULL);

SET FOREIGN_KEY_CHECKS = 1;
